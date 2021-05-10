#!/bin/bash
if [ "$#" -lt 1 ]; then
    echo "### Script for update monitor service artifacts ###"
    echo "Usage: $(basename "$0") <new version> [-f/--force]"
    exit 1
fi

NEW_VERSION=$1

if [ -n "$2" ] && { [ "$2" == "-f" ] || [ "$2" == "--force" ]; }; then
    FORCE_UPDATE="1"
fi

ARTIFACT="monitoring"

# shellcheck source=utils.sh
. "$(dirname "$0")/utils.sh"

require_root_user

config_service_env "" "$ARTIFACT"

if ! is_snapshot_version "$NEW_VERSION" && [ "$FORCE_UPDATE" != "1" ]; then
    ARTIFACT_JAR="$(get_artifact_name "$SERVICE_NAME").jar"
    ARTIFACT_VERSION="$(extract_and_read_artifact_version "$SERVICE_PATH/$ARTIFACT_JAR")"

    if [ "$ARTIFACT_VERSION" == "$NEW_VERSION" ]; then
        # Skip service
        echo "[$ARTIFACT $NEW_VERSION] is already installed!"
        exit 0
    fi
fi

echo "Updating [$SERVICE_NAME] at [$SERVICE_PATH]..."
download_service_artifacts "$ARTIFACT" "$NEW_VERSION" || exit 1

if is_daemon_running "$SERVICE_NAME"; then
    echo "Stopping [$SERVICE_NAME]..."
    sudo systemctl stop "$SERVICE_NAME"
fi

copy_service_artifacts "$ARTIFACT" || exit 1
update_monitor_configuration || exit 1

if is_daemon_installed "$SERVICE_NAME"; then
    extract_launcher_script "$ARTIFACT" || exit 1

    echo "Starting [$SERVICE_NAME]..."
    sudo systemctl start "$SERVICE_NAME" || exit $?
fi
