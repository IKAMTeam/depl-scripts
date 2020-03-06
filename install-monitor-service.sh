#!/bin/bash

function usage() {
    echo "### Script for install monitoring service as daemon and add new schema for monitoring ###"
    echo "Usage: $(basename "$0") <version> <owner_schema_username> <monitor_schema_username> <monitor_schema_password> <monitor_schema_connect_identifier> [aes_password]"
    echo " "
    echo "Where *_schema_connect_identifier is Oracle host:port:sid or host:port/service_name"
}

if [ "$#" -lt 5 ]; then
    usage
    exit 1
fi

VERSION=$1

# shellcheck disable=SC2034
DB_OWNER_USER=$2
# shellcheck disable=SC2034
DB_USER=$3
# shellcheck disable=SC2034
DB_PASSWORD=$4
# shellcheck disable=SC2034
DB_URL=$5
# shellcheck disable=SC2034
AES_PASSWORD=$6

ARTIFACT="monitoring"

# shellcheck source=utils.sh
. "$(dirname "$0")/utils.sh"

require_root_user

SERVICE_NAME="$(generate_service_name "" "$ARTIFACT")"

if ! is_daemon_installed "$SERVICE_NAME"; then
    config_service "" "$ARTIFACT" || exit 1
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

    (< "$ENV_CONF_EXTRACT_PATH" envsubst | tee "$SERVICE_PATH/${JAR_NAME}.conf") >/dev/null || exit 1
    (< "$SYSTEMD_SERVICE_EXTRACT_PATH" envsubst | tee "/usr/lib/systemd/system/${SERVICE_NAME}.service") >/dev/null || exit 1
    chown "$SERVICE_UN:$SERVICE_GROUP" "$SERVICE_PATH/${JAR_NAME}.conf" || exit 1

    echo "Enabling service [$SERVICE_NAME]..."
    systemctl enable "$SERVICE_NAME" || exit 1
fi

MONITOR_XML="$SERVICE_PATH/db-schemas.xml"

if [ ! -f "$MONITOR_XML" ]; then
    echo "Copying initial configuration [$MONITOR_XML]..."

    cp "$MONITOR_XML_TEMPLATE_NAME" "$MONITOR_XML" || exit 1
    chown "$SERVICE_UN:$SERVICE_GROUP" "$MONITOR_XML" || exit 1
fi

echo "Adding new schema to configuration [$MONITOR_XML]..."

MONITOR_XML_SCHEMA_PATH="$(mktemp --suffix="_schema_xml_$ARTIFACT")"
delete_on_exit "$MONITOR_XML_SCHEMA_PATH"
(< "$MONITOR_XML_SCHEMA_TEMPLATE_NAME" envsubst | tee "$MONITOR_XML_SCHEMA_PATH") >/dev/null || exit 1

sed "$(cat "$MONITOR_XML_SCHEMA_PATH")" "$MONITOR_XML" || exit 1
sed "/<schema-placeholder\/>/ {r $MONITOR_XML_SCHEMA_PATH
d}" "$MONITOR_XML" || exit 1

if is_daemon_running "$SERVICE_NAME"; then
    echo "Done. [$SERVICE_NAME] already started"
else
    echo "Done. You can start daemon with [systemctl start $SERVICE_NAME] command"
fi
