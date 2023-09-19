#!/bin/bash

function usage() {
    echo "### Script for install new website into Tomcat ###"
    echo "Usage: $(basename "$0") <website> <version> <owner_schema_username> <owner_schema_password> <user_schema_password> <pkg_schema_password> <connect_identifier> [platform_edition] [aes_password]"
    echo " "
    echo "Where connect_identifier is Oracle host:port:sid or host:port/service_name"
    echo "Where platform_edition is one of STANDARD/ENTERPRISE/ULTIMATE - defaults to ENTERPRISE"
    echo " "
    echo "If installation with the same name already exists, it will be updated with new settings"
}

if [ "$#" -lt 7 ]; then
    usage
    exit 1
fi

# shellcheck source=utils.sh
. "$(dirname "$0")/utils.sh"

require_root_user

WEBSITE=$1
VERSION=$2
DB_OWNER_USER=$3
DB_OWNER_PASSWORD=$4
DB_USER_PASSWORD=$5
DB_PKG_PASSWORD=$6
DB_URL=$7
PLATFORM_EDITION="$(echo "$8" | tr '[:lower:]' '[:upper:]')"
AES_PASSWORD=$9

if [ -z "$PLATFORM_EDITION" ]; then
    PLATFORM_EDITION="ENTERPRISE"
fi

SERVER_XML_FILE="$TOMCAT_PATH/conf/server.xml"
CONTEXT_XML_FILE="$TOMCAT_PATH/conf/Catalina/$WEBSITE/ROOT.xml"

ENGINE_XPATH="Service/Engine[@name=\"Catalina\"]"
HOST_XPATH="Host[@name=\"$WEBSITE\"]"
FULL_HOST_XPATH="$ENGINE_XPATH/$HOST_XPATH"

# Override existing installation if one with the same name already exists
if [ -n "$(read_xml_value "$SERVER_XML_FILE" "$FULL_HOST_XPATH" "name")" ]; then
    "$(dirname "$0")/setup/delete-xml-node.py" "$SERVER_XML_FILE" "$ENGINE_XPATH" "$HOST_XPATH" || exit 1
fi

# Delete existing configuration if exists
rm -rf "$TOMCAT_PATH/conf/Catalina/$WEBSITE"
rm -rf "$TOMCAT_PATH/conf/Catalina/sitename.onevizion.com"

cp -rf "$(dirname "$0")"/setup/tomcat/conf/Catalina/* "$TOMCAT_PATH/conf/Catalina" || exit 1
mv "$TOMCAT_PATH/conf/Catalina/sitename.onevizion.com" "$TOMCAT_PATH/conf/Catalina/$WEBSITE" || exit 1

"$(dirname "$0")/setup/update-xml-value.py" "$CONTEXT_XML_FILE" '' docBase "\${catalina.home}/$WEBSITE-webapp" || exit 1
"$(dirname "$0")/setup/update-xml-value.py" "$CONTEXT_XML_FILE" 'Parameter[@name="app.serverUrl"]' value "$WEBSITE" || exit 1
"$(dirname "$0")/setup/update-xml-value.py" "$CONTEXT_XML_FILE" 'Parameter[@name="web.dbSid"]' value "$DB_URL" || exit 1
"$(dirname "$0")/setup/update-xml-value.py" "$CONTEXT_XML_FILE" 'Parameter[@name="web.dbOwner"]' value "$DB_OWNER_USER" || exit 1
"$(dirname "$0")/setup/update-xml-value.py" "$CONTEXT_XML_FILE" 'Parameter[@name="web.dbOwnerPassword"]' value "$DB_OWNER_PASSWORD" || exit 1
"$(dirname "$0")/setup/update-xml-value.py" "$CONTEXT_XML_FILE" 'Parameter[@name="web.dbUser"]' value "${DB_OWNER_USER}_user" || exit 1
"$(dirname "$0")/setup/update-xml-value.py" "$CONTEXT_XML_FILE" 'Parameter[@name="web.dbUserPassword"]' value "$DB_USER_PASSWORD" || exit 1
"$(dirname "$0")/setup/update-xml-value.py" "$CONTEXT_XML_FILE" 'Parameter[@name="web.dbPkg"]' value "${DB_OWNER_USER}_pkg" || exit 1
"$(dirname "$0")/setup/update-xml-value.py" "$CONTEXT_XML_FILE" 'Parameter[@name="web.dbPkgPassword"]' value "$DB_PKG_PASSWORD" || exit 1
"$(dirname "$0")/setup/update-xml-value.py" "$CONTEXT_XML_FILE" 'Parameter[@name="app.serverUrl"]' value "https://$WEBSITE" || exit 1
"$(dirname "$0")/setup/update-xml-value.py" "$CONTEXT_XML_FILE" 'Parameter[@name="web.platformEdition"]' value "$PLATFORM_EDITION" || exit 1

"$(dirname "$0")/setup/insert-xml-node.py" "$SERVER_XML_FILE" "$(dirname "$0")/$SERVER_XML_HOST_TEMPLATE_NAME" \
    'Service/Engine[@name="Catalina"]' || exit 1

"$(dirname "$0")/setup/update-xml-value.py" "$SERVER_XML_FILE" 'Service/Engine/Host[last()]' \
    name "$WEBSITE" || exit 1

# Set AES password if specified
if [ -n "$AES_PASSWORD" ]; then
    mkdir -p "$TOMCAT_PATH/$WEBSITE"
    echo "aesPassword=$AES_PASSWORD" > "$TOMCAT_PATH/$WEBSITE/ov.properties" || exit 1
fi

recalculate_tomcat_metaspace_size || exit 1

"$(dirname "$0")/update-ov.sh" "$WEBSITE" "tomcat" "$VERSION" || exit 1
