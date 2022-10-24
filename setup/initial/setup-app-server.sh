#!/bin/bash

function usage() {
    echo "### This script will automatically set up the services needed to run on the app server ###"
    echo "Before run this script you need to install Java 11 on server"
    echo " "
    echo "Usage: $(basename "$0") <config file>"
    echo " "
    echo "Example: $(basename "$0") setup-server.conf"
}

if [ "$#" -ne 1 ]; then
    usage
    exit 1
fi

# shellcheck source=setup-utils.sh
. "$(dirname "$0")/setup-utils.sh"

require_root_user

CONFIG_FILE="$1"
CONFIG_DATA="$(cat "$CONFIG_FILE")"

set -o allexport
eval "$CONFIG_DATA"
set +o allexport

set -o errexit
set -o pipefail

init_credentials

# Update timezone
if [ -n "$SET_TIMEZONE" ]; then
    ln -sf "/usr/share/zoneinfo/$SET_TIMEZONE" /etc/localtime
fi

# Add rules for sudo into /etc/sudoers for integration-scheduler:
echo "integration-scheduler ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/integration-scheduler
chmod 440 /etc/sudoers.d/integration-scheduler

# Install services for this instance
"$SCRIPTS_PATH/install-daemon-service.sh" "$WEBSITE" services "$VERSION" --aes-password "$AES_PASSWORD" "${DB_OWNER_USER}/${DB_OWNER_PASSWORD}@$DB_URL" \
    "${DB_OWNER_USER}_user/${DB_USER_PASSWORD}@$DB_URL" "${DB_OWNER_USER}_rpt/${DB_RPT_PASSWORD}@$DB_URL"
"$SCRIPTS_PATH/install-daemon-service.sh" "$WEBSITE" integration-scheduler "$VERSION" --aes-password "$AES_PASSWORD" "${DB_OWNER_USER}/${DB_OWNER_PASSWORD}@$DB_URL"
"$SCRIPTS_PATH/install-cron-service.sh" "$WEBSITE" syncs3 "$VERSION" --aes-password "$AES_PASSWORD" "0 3 * * *" "${DB_OWNER_USER}/${DB_OWNER_PASSWORD}@$DB_URL"

if [ -n "$MONITOR_VERSION" ]; then
    "$SCRIPTS_PATH/install-monitor-service.sh" "$MONITOR_VERSION" "$DB_OWNER_USER" "$MONITOR_DB_USER" "$MONITOR_DB_PASSWORD" "$DB_URL" "$AES_PASSWORD"

    if [ "$MONITOR_INSTALL_CONFIG_REFRESH_SCRIPT" == "1" ]; then
      "$SCRIPTS_PATH/install-cron-service.sh" monitoring-refresh-config
    fi
fi

# Start up services
systemctl start "${WEBSITE}_services"
systemctl start "${WEBSITE}_integration-scheduler"

if [ -n "$MONITOR_VERSION" ]; then
    systemctl start "monitoring"
fi

# Finished
echo "Application server setup complete."
