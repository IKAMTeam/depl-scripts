#!/bin/bash

function usage() {
    echo "### Script to install monitoring service as daemon ###"
    echo "Usage: $(basename "$0") [version]"
    echo "If version is not specified - latest will be used"
}

if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    usage
    exit
fi

VERSION=$1
ARTIFACT="monitoring"

# shellcheck source=utils.sh
. "$(dirname "$0")/utils.sh"

require_root_user

if [ -z "$VERSION" ] \
    && ! VERSION="$(find_artifact_latest_version \
        "$MONITORING_REPO_URL" \
        "$MONITORING_REPO_UN" \
        "$MONITORING_REPO_PWD" \
        "$MONITOR_GROUP_ID_URL" \
        "$ARTIFACT")"; then

    exit 1
fi

config_service_env "" "$ARTIFACT"
if is_daemon_installed "$SERVICE_NAME"; then
    ARTIFACT_JAR="$(get_artifact_name "$SERVICE_NAME").jar"
    ARTIFACT_VERSION="$(extract_and_read_artifact_version "$SERVICE_PATH/$ARTIFACT_JAR")"

    echo "Daemon [$SERVICE_NAME] of version [$ARTIFACT_VERSION] is already installed, nothing to do"
else
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

    (< "$SYSTEMD_SERVICE_EXTRACT_PATH" envsubst | tee "/usr/lib/systemd/system/${SERVICE_NAME}.service") >/dev/null || exit 1

    ENV_CONF_FILE="$(get_service_conf_file "$ARTIFACT")"

    # Replace $ -> \\$ for prevent eat it on launch stage
    export JAR_OPTS=${JAR_OPTS//$/\\\\$}
    (< "$ENV_CONF_EXTRACT_PATH" envsubst | tee "$ENV_CONF_FILE") >/dev/null || exit 1
    chown "$SERVICE_UN:$SERVICE_GROUP" "$ENV_CONF_FILE" || exit 1

    echo "Enabling service [$SERVICE_NAME]..."
    systemctl enable "$SERVICE_NAME" || exit 1
fi

MONITOR_XML="$SERVICE_PATH/db-schemas.xml"

if [ ! -f "$MONITOR_XML" ]; then
    echo "Copying initial empty configuration to [$MONITOR_XML]..."

    cp "$(dirname "$0")/$MONITOR_XML_TEMPLATE_NAME" "$MONITOR_XML" || exit 1
    chown "$SERVICE_UN:$SERVICE_GROUP" "$MONITOR_XML" || exit 1

    # To allow group write access for monitoring-refresh-config service
    chmod 660 "$MONITOR_XML" || exit 1
fi

if is_daemon_running "$SERVICE_NAME"; then
    echo "Done. [$SERVICE_NAME] already started"
else
    echo "Done. You can start daemon with [systemctl start $SERVICE_NAME] command"
fi
