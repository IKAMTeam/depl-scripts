import json
import os
import shutil
import urllib.request
import boto3
import onevizion
import xmlhelper

from onevizion import Message
from xml.etree import ElementTree
from random import SystemRandom
from time import sleep

def fetch_ec2_instance_data():
    TokenRequest = urllib.request.Request('http://169.254.169.254/latest/api/token', method='PUT', headers={'X-aws-ec2-metadata-token-ttl-seconds': '21600'})
    TOKEN = urllib.request.urlopen(TokenRequest).read().decode()
    MetadataRequest = urllib.request.Request('http://169.254.169.254/latest/dynamic/instance-identity/document', headers={'X-aws-ec2-metadata-token': TOKEN})
    return json.loads(urllib.request.urlopen(MetadataRequest).read().decode())

def fetch_ec2_instance_id():
    return fetch_ec2_instance_data()['instanceId']

def fetch_ssm_region():
    # Gov Cloud is in a different account, so we need to change region for SSM only
    if 'us-gov' in fetch_ec2_instance_data()['region']:
        ssm_region = 'us-gov-east-1'
    else:
        ssm_region = 'us-east-1'
    return ssm_region

class Settings:
    SPREAD_LOAD_MAX_SLEEP_MINUTES = 4
    AWS_SSM_REGION = fetch_ssm_region()
    AWS_SSM_PARAMETER_NAME = 'MonitoringOneTeam'
    MONITOR_CONFIG_FILE = os.getenv('MONITOR_CONFIG_FILE')
    TRACKOR_HOSTNAME = 'trackor.onevizion.com'
    TRACKOR_TYPE_WEBSITE = 'Website'
    TRACKOR_TYPE_CONFIG_ATTRIB = 'ConfigAttrib'
    TRACKOR_TO_XML_TRANSLATION_DICT = {
        'Database.DB_CONNECTION_STRING': 'url',
        'TRACKOR_ID': 'trackor-id',
        'TRACKOR_KEY': 'website',
        'VQS_WEB_DBSCHEMA': 'main-user',
        'WEB_MONITOR_USER': 'monitor-user',
        'WEB_MONITOR_PASSWORD': 'monitor-password',
        'WEB_MONITORING_ENABLED': 'enabled',
        'WEB_MONITORS_DISABLED': 'disable-monitors',
        'WEB_ENCRYPTION_KEY': 'aes-password'
    }
    REPORT_CHECK_ATTRIBUTE_EQUALITY_NAMES = [
        'enabled',
        'disable-monitors',
        'url',
        'main-user',
        'monitor-user',
        'monitor-password'
    ]
    REPORT_HIDE_ATTRIBUTE_VALUE_NAMES = ['password', 'aes-password', 'monitor-password']
    DEFAULT_DB_SCHEMAS_XML_CONTENT = """<?xml version="1.0"?>
        <root>
            <schemas>
            </schemas>
            <aws-sqs>
            </aws-sqs>
            <error-email>
            </error-email>
            <warning-email>
            </warning-email>
            <suspend>false</suspend>
            <disable-monitors></disable-monitors>
        </root>
        """


class JsonData:
    def __init__(self,
                 error_mail_json,
                 warning_mail_json,
                 aws_sqs_json,
                 aws_sqs_trackor_integration_json,
                 root_config_json,
                 schemas_json):
        self.error_mail_json = error_mail_json
        self.warning_mail_json = warning_mail_json
        self.aws_sqs_json = aws_sqs_json
        self.aws_sqs_trackor_integration_json = aws_sqs_trackor_integration_json
        self.root_config_json = root_config_json
        self.schemas_json = schemas_json


class XmlData:
    def __init__(self,
                 schemas_xml,
                 aws_sqs_xml,
                 error_mail_xml,
                 warning_mail_xml,
                 suspend_xml,
                 disable_monitors_xml):
        self.schemas_xml = schemas_xml
        self.aws_sqs_xml = aws_sqs_xml
        self.error_mail_xml = error_mail_xml
        self.warning_mail_xml = warning_mail_xml
        self.suspend_xml = suspend_xml
        self.disable_monitors_xml = disable_monitors_xml


class XmlElementDto:
    def __init__(self, old_xml_element, new_xml_element):
        self.old_xml_element = old_xml_element
        self.new_xml_element = new_xml_element


class ConfigChanges:
    def __init__(self,
                 new_websites,
                 removed_websites,
                 updated_websites,
                 updated_website_elements):
        self.new_websites = new_websites
        self.removed_websites = removed_websites
        self.updated_websites = updated_websites
        self.updated_website_elements = updated_website_elements

    def is_config_changed(self):
        return len(self.new_websites) + len(self.removed_websites) + len(self.updated_websites) > 0

    def generate_report(self):
        if self.is_config_changed():
            report_message = 'Changes have been made to Monitoring Configuration.'

            if len(self.new_websites) > 0:
                report_message += '\n\nNew Websites added to Monitoring:\n' + '\n'.join(self.new_websites)
            if len(self.removed_websites) > 0:
                report_message += '\n\nWebsites removed from Monitoring:\n' + '\n'.join(self.removed_websites)
            if len(self.updated_websites) > 0:
                report_message += '\n\nWebsites that have Monitoring Configuration changes:'
                for updated_website_element in self.updated_website_elements:
                    report_message += ConfigChanges.generate_updated_website_report(updated_website_element)
        else:
            report_message = 'No changes in Monitoring Configuration'

        return report_message

    @staticmethod
    def generate_updated_website_report(updated_website_element):
        old_xml_element = updated_website_element.old_xml_element
        new_xml_element = updated_website_element.new_xml_element
        website = new_xml_element.find('website').text

        def attr_not_equals(attr_name):
            old_attr = old_xml_element.find(attr_name)
            new_attr = new_xml_element.find(attr_name)

            old_text = old_attr.text if old_attr is not None else None
            new_text = new_attr.text if new_attr is not None else None

            if old_text is None:
                old_text = ''
            if new_text is None:
                new_text = ''

            return new_text != old_text

        def value_of(attr_name):
            if attr_name in Settings.REPORT_HIDE_ATTRIBUTE_VALUE_NAMES:
                return '\n-->{attr_name} changed'.format(attr_name=attr_name)
            else:
                old_xml_attr = old_xml_element.find(attr_name)
                new_xml_attr = new_xml_element.find(attr_name)
                return "\n-->{attr_name} changed from '{old_text}' to '{new_text}'".format(
                    attr_name=attr_name,
                    old_text=old_xml_attr.text if old_xml_attr is not None else '',
                    new_text=new_xml_attr.text if old_xml_attr is not None else ''
                )

        website_report_message = '\n' + website

        for attribute_name in Settings.REPORT_CHECK_ATTRIBUTE_EQUALITY_NAMES:
            if attr_not_equals(attribute_name):
                website_report_message += value_of(attribute_name)

        return website_report_message


# region AWS
def fetch_onevizion_configuration_from_ssm():
    aws_client = boto3.client('ssm', region_name=Settings.AWS_SSM_REGION)
    parameters = aws_client.get_parameters(Names=[Settings.AWS_SSM_PARAMETER_NAME])
    onevizion_conf_json = \
        next(item for item in parameters['Parameters'] if item['Name'] == Settings.AWS_SSM_PARAMETER_NAME)['Value']

    return json.loads(onevizion_conf_json)


# endregion


# region Help functions
def convert_json_data_to_xml(json_data):
    schemas_xml = xmlhelper.rows_to_xml_elements(json_data.schemas_json, 'schemas', 'schema')
    aws_sqs_xml = ElementTree.Element('aws-sqs')
    aws_sqs_xml.extend((xmlhelper.dict_to_xml_element(json_data.aws_sqs_json[0], 'sqs'),
                        xmlhelper.dict_to_xml_element(json_data.aws_sqs_trackor_integration_json[0], 'sqs')))
    error_mail_xml = xmlhelper.dict_to_xml_element(json_data.error_mail_json, 'error-email')
    warning_mail_xml = xmlhelper.dict_to_xml_element(json_data.warning_mail_json, 'warning-email')

    if 'suspend' not in json_data.root_config_json:
        raise Exception('No "suspend" found in config attributes')
    if 'disable-monitors' not in json_data.root_config_json:
        raise Exception('No "disable-monitors" found in config attributes')

    suspend_xml = ElementTree.Element('suspend')
    suspend_xml.text = json_data.root_config_json['suspend']
    disable_monitors_xml = ElementTree.Element('disable-monitors')
    disable_monitors_xml.text = json_data.root_config_json['disable-monitors']

    return XmlData(schemas_xml=schemas_xml,
                   aws_sqs_xml=aws_sqs_xml,
                   error_mail_xml=error_mail_xml,
                   warning_mail_xml=warning_mail_xml,
                   suspend_xml=suspend_xml,
                   disable_monitors_xml=disable_monitors_xml)


def translate_trackor_to_xml_field_names(source_rows=None, translation_dictionary=None):
    def convert_value(input_value):
        if input_value == '1':
            output_value = 'true'
        elif input_value == '0':
            output_value = 'false'
        elif input_value is None:
            output_value = ''
        else:
            output_value = str(input_value)
        return output_value

    if source_rows is None:
        source_rows = []
    if translation_dictionary is None:
        translation_dictionary = {}

    rows = []
    for row in source_rows:
        child_dict = {}
        for key, value in row.items():
            if key not in translation_dictionary:
                raise Exception(f'Unable to translate key {key}. Row: {row}. Translations: {translation_dictionary}')

            child_dict[translation_dictionary[key]] = convert_value(value)
        rows.append(child_dict)
    return rows


def trace_json(json_object):
    Message(json.dumps(json_object, indent=2), 1)


def trace_xml(xml_element):
    Message(xmlhelper.prettify_xml(xml_element), 1)


def find_config_changes(new_xml_root_element, old_xml_root_element):
    new_websites = []
    removed_websites = []
    updated_websites = []
    updated_website_elements = []

    for new_xml_schema in new_xml_root_element.findall('./schemas/schema'):
        new_xml_website = new_xml_schema.find('website').text
        old_xml_websites = old_xml_root_element.findall(f"./schemas/schema[website='{new_xml_website}']")

        if len(old_xml_websites) == 0:
            new_websites.append(new_xml_website)
        elif xmlhelper.compare_xml_elements(new_xml_schema, old_xml_websites[0]) != 0:
            updated_websites.append(new_xml_website)
            updated_website_elements.append(XmlElementDto(new_xml_element=new_xml_schema,
                                                          old_xml_element=old_xml_websites[0]))

    for old_xml_schema in old_xml_root_element.findall('./schemas/schema'):
        old_xml_website_attr = old_xml_schema.find('website')
        if old_xml_website_attr is not None:
            old_xml_website = old_xml_website_attr.text
            new_xml_website = new_xml_root_element.findall(f"./schemas/schema[website='{old_xml_website}']")

            if len(new_xml_website) == 0:
                removed_websites.append(old_xml_website)
        else:
            removed_websites.append('<website without name>')

    return ConfigChanges(new_websites=new_websites,
                         removed_websites=removed_websites,
                         updated_websites=updated_websites,
                         updated_website_elements=updated_website_elements)


# endregion

# region Fetch functions
def fetch_required_configs():
    websites = fetch_websites_for_current_instance()
    if len(websites.errors) > 0:
        raise Exception(f'Problem Getting Website List: {websites.errors}')
    elif len(websites.jsonData) == 0:
        raise Exception('No Websites found!')

    error_mail_json = fetch_config_attributes('error-email')
    warning_mail_json = fetch_config_attributes('warning-email')
    aws_sqs_json = [fetch_config_attributes('aws-sqs')]
    aws_sqs_trackor_integration_json = [fetch_config_attributes('aws-sqs-trackor-integration')]
    root_config_json = fetch_config_attributes('monitoring')

    schemas_json = translate_trackor_to_xml_field_names(websites.jsonData, Settings.TRACKOR_TO_XML_TRANSLATION_DICT)
    trace_json(schemas_json)

    return JsonData(error_mail_json=error_mail_json,
                    warning_mail_json=warning_mail_json,
                    aws_sqs_json=aws_sqs_json,
                    aws_sqs_trackor_integration_json=aws_sqs_trackor_integration_json,
                    root_config_json=root_config_json,
                    schemas_json=schemas_json)


def fetch_websites_for_current_instance():
    websites = onevizion.Trackor(
        trackorType=Settings.TRACKOR_TYPE_WEBSITE,
        paramToken=Settings.TRACKOR_HOSTNAME
    )
    websites.read(
        filters={
            'VQS_WEB_ACTIVE': 1,
            'Server.EC2_INSTANCE_ID': fetch_ec2_instance_id()
        },
        fields=[
            'Database.DB_CONNECTION_STRING',
            'TRACKOR_KEY',
            'VQS_WEB_DBSCHEMA',
            'WEB_MONITOR_USER',
            'WEB_MONITOR_PASSWORD',
            'WEB_MONITORING_ENABLED',
            'WEB_MONITORS_DISABLED',
            'WEB_ENCRYPTION_KEY'
        ]
    )
    return websites


def fetch_config_attributes(config_key):
    config_attrib = onevizion.Trackor(
        trackorType=Settings.TRACKOR_TYPE_CONFIG_ATTRIB,
        paramToken=Settings.TRACKOR_HOSTNAME
    )
    config_attrib.read(
        filters={
            'Config.TRACKOR_KEY': f'"{config_key}"'
        },
        fields=[
            'TRACKOR_KEY',
            'CONFATTRIB_VALUE'
        ]
    )

    if len(config_attrib.errors) > 0:
        raise Exception(f'Unable to find config attributes {config_key}')
    elif len(config_attrib.jsonData) == 0:
        raise Exception(f'Config attributes for {config_key} are not found.')
    else:
        config = {}
        for row in config_attrib.jsonData:
            config[row['TRACKOR_KEY']] = row['CONFATTRIB_VALUE']
        trace_json(config)
        return config



# endregion


def load_existing_monitoring_configuration_as_xml_tree():
    # Write default configuration
    if not os.path.exists(Settings.MONITOR_CONFIG_FILE):
        with open(Settings.MONITOR_CONFIG_FILE, 'w+') as f:
            f.write(Settings.DEFAULT_DB_SCHEMAS_XML_CONTENT)

    return ElementTree.parse(Settings.MONITOR_CONFIG_FILE)


def sleep_to_spread_load():
    """Sleep random time from 0 to SPREAD_LOAD_MAX_SLEEP_MINUTES minutes to spread load to website because this
       script will run at the same time from many installations
    """

    sleep_time_seconds = SystemRandom().randint(1, Settings.SPREAD_LOAD_MAX_SLEEP_MINUTES * 60)
    sleep(sleep_time_seconds)


def check_monitoring_config_exists_and_writeable_or_quit():
    service_dir = os.path.dirname(Settings.MONITOR_CONFIG_FILE)

    if not os.path.isfile(Settings.MONITOR_CONFIG_FILE) and not os.path.isdir(service_dir):
        Message(f'{Settings.MONITOR_CONFIG_FILE} file is not exists and parent directory is not found', 1)
        quit(2)
    if not os.access(service_dir, os.W_OK):
        Message(f'{service_dir} directory is not writable', 1)
        quit(3)
    if not os.access(Settings.MONITOR_CONFIG_FILE, os.W_OK):
        Message(f'{Settings.MONITOR_CONFIG_FILE} file is not writable', 1)
        quit(3)


def main():
    if Settings.MONITOR_CONFIG_FILE is None or len(Settings.MONITOR_CONFIG_FILE) == 0:
        Message('MONITOR_CONFIG_FILE environment variable is empty')
        quit(1)

    # Uncomment this line to enable debug messages. Pay attention - passwords will be exposed to standard output
    # onevizion.Config['Verbosity'] = 1

    check_monitoring_config_exists_and_writeable_or_quit()

    onevizion.Config['ParameterData'] = fetch_onevizion_configuration_from_ssm()

    sleep_to_spread_load()

    json_data = fetch_required_configs()
    xml_data = convert_json_data_to_xml(json_data)

    old_xml_root_element = load_existing_monitoring_configuration_as_xml_tree()

    # Create new db-schemas.xml
    new_xml_root_element = ElementTree.Element('root')
    new_xml_root_element.extend((xml_data.schemas_xml,
                                 xml_data.aws_sqs_xml,
                                 xml_data.error_mail_xml,
                                 xml_data.warning_mail_xml,
                                 xml_data.suspend_xml,
                                 xml_data.disable_monitors_xml))
    trace_xml(new_xml_root_element)

    config_changes = find_config_changes(new_xml_root_element, old_xml_root_element)
    Message(config_changes.generate_report())

    if config_changes.is_config_changed():
        with open(Settings.MONITOR_CONFIG_FILE + '.new', 'w') as f:
            f.write(xmlhelper.prettify_xml(new_xml_root_element))
        shutil.move(Settings.MONITOR_CONFIG_FILE + '.new', Settings.MONITOR_CONFIG_FILE)


if __name__ == '__main__':
    main()
