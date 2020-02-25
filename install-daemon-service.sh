#!/bin/bash

function usage() {
    echo "### Script for install new service as daemon ###"
    echo "Usage: $(basename "$0") <website> <artifact> [--suffix <suffix>] <version> <jar launch args>"
    echo " "
    echo "Usage for services: $(basename "$0") <website> services [--suffix <suffix>] <version> <owner_schema_username>/<owner_schema_password>@<owner_schema_connect_identifier> <user_schema_username>/<user_schema_password>@<user_schema_connect_identifier> <rpt_schema_username>/<rpt_schema_password>@<rpt_schema_connect_identifier> [report_scheduler_name] [services_to_run]"
    echo "Supported values for [services_to_run]: mail_service,trackor_mail,report_scheduler,rule_service (comma separated wout spaces)"
    echo " "
    echo "Usage for report-scheduler: $(basename "$0") <website> report-scheduler [--suffix <suffix>] <version> <owner_schema_username>/<owner_schema_password>@<owner_schema_connect_identifier> <user_schema_username>/<user_schema_password>@<user_schema_connect_identifier> <rpt_schema_username>/<rpt_schema_password>@<rpt_schema_connect_identifier> [report_scheduler_name]"
    echo " "
    echo "Usage for integration-scheduler: $(basename "$0") <website> integration-scheduler [--suffix <suffix>] <version> <owner_schema_username>/<owner_schema_password>@<owner_schema_connect_identifier>"
    echo " "
    echo "Where *_schema_connect_identifier is Oracle host:port:sid or host:port/service_name"
}

if [ "$#" -lt 3 ]; then
    usage
    exit 1
fi

WEBSITE=$1
ARTIFACT=$2

shift
shift

if [ "$1" == "--suffix" ]; then
    SUFFIX=$2
    shift
    shift
fi

VERSION=$1
shift

if [ "$#" -eq 0 ]; then
    usage
    exit 1
fi

# shellcheck disable=SC2034
export JAR_OPTS=$*

# shellcheck source=utils.sh
. "$(dirname "$0")/utils.sh"

require_root_user
config_service "$WEBSITE" "$ARTIFACT" "$SUFFIX" || exit 1
download_service_artifacts "$ARTIFACT" "$VERSION" || exit 1

copy_service_artifacts "$ARTIFACT" || exit 1

echo "Installing daemon [$SERVICE_NAME] for [$JAR_PATH]..."

extract_launcher_script "$ARTIFACT" || exit 1

ENV_CONF_EXTRACT_PATH="$(mktemp --suffix="_env_$ARTIFACT")"
delete_on_exit "$ENV_CONF_EXTRACT_PATH"
extract_environment_conf "$ARTIFACT" "$ENV_CONF_EXTRACT_PATH" || exit 1

SYSTEMD_SERVICE_EXTRACT_PATH="$(mktemp --suffix="_systemd_service_$ARTIFACT")"
delete_on_exit "$SYSTEMD_SERVICE_EXTRACT_PATH"
extract_systemd_service "$ARTIFACT" "$SYSTEMD_SERVICE_EXTRACT_PATH" || exit 1

# Replace $ -> \$ for prevent bash eat it on launch stage
export JAR_OPTS=${JAR_OPTS/$/\\$}

(sudo cat "$ENV_CONF_EXTRACT_PATH" | envsubst | sudo tee "$SERVICE_PATH/${JAR_NAME}.conf") >/dev/null || exit 1
(sudo cat "$SYSTEMD_SERVICE_EXTRACT_PATH" | envsubst | sudo tee "/usr/lib/systemd/system/${SERVICE_NAME}.service") >/dev/null || exit 1

echo "Enabling service [$SERVICE_NAME]..."
sudo systemctl enable "$SERVICE_NAME" || exit 1

echo "You can start daemon with [sudo systemctl start $SERVICE_NAME] command"
