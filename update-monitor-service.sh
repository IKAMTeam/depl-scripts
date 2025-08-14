#!/bin/bash

function usage() {
    echo "### Script to update monitor service artifacts ###"
    echo "Usage: $(basename "$0") [new version] [-f/--force]"
    echo "If new version is not specified - latest will be used"
}

if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    usage
    exit
fi

ARTIFACT="monitoring"

if { [ "$1" == "-f" ] || [ "$1" == "--force" ]; }; then
    # No version
    FORCE_UPDATE="1"
elif { [ "$2" == "-f" ] || [ "$2" == "--force" ]; }; then
    NEW_VERSION="$1"
    FORCE_UPDATE="1"
elif [ -n "$1" ]; then
    NEW_VERSION="$1"
else
    echo "Finding latest version of the artifact"
    if ! NEW_VERSION="$(find_artifact_latest_version \
        "$MONITORING_REPO_URL" \
        "$MONITORING_REPO_UN" \
        "$MONITORING_REPO_PWD" \
        "$MONITOR_GROUP_ID_URL" \
        "$ARTIFACT")"; then

        exit 1
    fi

    echo "Latest version: $NEW_VERSION"
fi

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

if is_daemon_installed "$SERVICE_NAME"; then
    extract_launcher_script "$ARTIFACT" || exit 1

    echo "Starting [$SERVICE_NAME]..."
    sudo systemctl start "$SERVICE_NAME" || exit $?
fi
