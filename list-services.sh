#!/bin/bash
if [ -n "$1" ] && { [ "$1" == "--short-format" ] || [ "$1" == "-s" ]; }; then
    SHORT_FORMAT="1"
fi

# shellcheck source=utils.sh
. "$(dirname "$0")/utils.sh"

if [ -z "$SHORT_FORMAT" ]; then
    echo "List of available OneVizion services:"
fi

find "$SERVICES_PATH" -maxdepth 1 -type d -print0 | while read -r -d '' SERVICE_DIR; do
    SERVICE_NAME="$(basename "$SERVICE_DIR")"
    ARTIFACT_JAR="$(get_artifact_name "$SERVICE_NAME").jar"

    if ! sudo test -f "$SERVICE_DIR/$ARTIFACT_JAR"; then
        continue
    fi

    if [ -z "$SHORT_FORMAT" ]; then
        ARTIFACT_VERSION="$(extract_artifact_version "$SERVICE_DIR/$ARTIFACT_JAR")"

        if is_daemon_installed "$SERVICE_NAME"; then
            if is_daemon_running "$SERVICE_NAME"; then
                IS_RUNNING="\e[32mrunning\e[0m"
            else
                IS_RUNNING="\e[31mnot running\e[0m"
            fi

            echo -e "  \e[1m$SERVICE_NAME \e[0m($SERVICE_DIR) [\e[42ma systemd service\e[0m, $IS_RUNNING]: \e[4m$ARTIFACT_VERSION \e[0m"
        elif is_cron_installed "$SERVICE_NAME"; then
            echo -e "  \e[1m$SERVICE_NAME \e[0m($SERVICE_DIR) [\e[42ma cron scheduled service\e[0m]: \e[4m$ARTIFACT_VERSION \e[0m"
        else
            echo -e "  \e[1m$SERVICE_NAME \e[0m($SERVICE_DIR) [\e[41mnot a systemd service or cron scheduled\e[0m]: \e[4m$ARTIFACT_VERSION \e[0m"
        fi
    else
        echo "$SERVICE_NAME"
    fi
done
