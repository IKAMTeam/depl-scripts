#!/bin/bash

ARTIFACT="monitoring"

# shellcheck source=utils.sh
. "$(dirname "$0")/utils.sh"

require_root_user

config_service_env "" "$ARTIFACT"
check_service_exists_or_exit "$SERVICE_NAME"

if ! is_daemon_installed "$SERVICE_NAME"; then
    echo "Service is not installed as daemon"
    exit 1
fi

systemctl stop "$SERVICE_NAME"

echo "Disabling service [$SERVICE_NAME]..."
systemctl disable "$SERVICE_NAME"

echo "Removing service data [$SERVICE_NAME]..."
rm -rf "/usr/lib/systemd/system/${SERVICE_NAME}.service" "$SERVICE_PATH"
