#!/bin/bash
if [ "$#" -lt 1 ]; then
    echo "### Script for complete uninstall service scheduled to periodically run ###"
    echo "Usage: $(basename "$0") <service name> [--force/-f]"
    exit 1
fi

SERVICE_NAME=$1
FORCE="0"

if [ -n "$2" ] && { [ "$2" == "-f" ] || [ "$2" == "--force" ]; }; then
    FORCE="1"
fi

# shellcheck source=utils.sh
. "$(dirname "$0")/utils.sh"

require_root_user
check_service_exists_or_exit "$SERVICE_NAME"

if ! is_cron_installed "$SERVICE_NAME"; then
    echo "Service is not installed at cron"
    if [ "$FORCE" != "1" ]; then
        exit 1
    fi
fi

# shellcheck disable=SC2153
SERVICE_PATH="$SERVICES_PATH/$SERVICE_NAME"
SERVICE_UN="$(get_artifact_name "$SERVICE_NAME")"
CRON_LAUNCHER_SCRIPT_PATH="$SERVICE_PATH/cron-launcher.sh"

echo "Dropping record from crontab..."
sudo crontab -u "$SERVICE_UN" -l | grep -v "$CRON_LAUNCHER_SCRIPT_PATH" | sudo crontab -u "$SERVICE_UN" - || exit 1

echo "Removing service data [$SERVICE_NAME]..."
sudo rm -rf "$SERVICE_PATH"
