#!/bin/bash
if [ "$#" -lt 1 ]; then
    echo "### Script for completely uninstall service daemon ###"
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

if ! is_daemon_installed "$SERVICE_NAME"; then
    echo "Service is not installed as daemon"
    if [ "$FORCE" != "1" ]; then
        exit 1
    fi
fi

systemctl stop "$SERVICE_NAME"

echo "Disabling service [$SERVICE_NAME]..."
systemctl disable "$SERVICE_NAME"

# shellcheck disable=SC2153
SERVICE_PATH="$SERVICES_PATH/$SERVICE_NAME"

echo "Removing service data [$SERVICE_NAME]..."
rm -rf "/usr/lib/systemd/system/${SERVICE_NAME}.service" "$SERVICE_PATH"
