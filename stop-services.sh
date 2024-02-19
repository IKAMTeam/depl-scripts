#!/bin/bash

function usage() {
    echo "### Script to stop all services for specified website ###"
    echo "Usage: $(basename "$0") <website>"
}

if [ "$#" -lt 1 ]; then
    usage
    exit 1
fi

# shellcheck source=utils.sh
. "$(dirname "$0")/utils.sh"

require_root_user

MATCH_WEBSITE=$1

mapfile -t ALL_SERVICE_NAMES < <("$(dirname "$0")/list-services.sh" --short-format)
STOP_SERVICE_COUNT=0

for SERVICE_NAME in "${ALL_SERVICE_NAMES[@]}"; do
    WEBSITE="$(get_website_name "$SERVICE_NAME")"
    if [ "$WEBSITE" != "$MATCH_WEBSITE" ]; then
        # Skip service
        continue
    fi

    ARTIFACT="$(get_artifact_name "$SERVICE_NAME")"
    ARTIFACT_JAR="${ARTIFACT}.jar"

    # shellcheck disable=SC2153
    SERVICE_PATH="$SERVICES_PATH/$SERVICE_NAME"

    if [ ! -f "$SERVICE_PATH/$ARTIFACT_JAR" ]; then
        # Python services are not supported
        continue
    fi

    if is_daemon_installed "$SERVICE_NAME"; then
        if is_daemon_running "$SERVICE_NAME"; then
            echo "Stopping [$SERVICE_NAME]..."
            systemctl stop "$SERVICE_NAME"

            (( STOP_SERVICE_COUNT++ ))
        else
            echo "[$SERVICE_NAME] is not running"
        fi
    fi
done

if [ "$STOP_SERVICE_COUNT" -eq 0 ]; then
    echo "No services to stop found for website [$MATCH_WEBSITE]"
fi
