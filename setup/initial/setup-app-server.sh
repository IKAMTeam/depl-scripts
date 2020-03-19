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

# shellcheck source=setup-server.conf.template
. "$CONFIG_FILE"

set -o errexit
set -o pipefail

init_credentials

# Update timezone to EST
ln -sf /usr/share/zoneinfo/US/Eastern /etc/localtime

# Test database connection
java -jar "$SCRIPTS_DIR/setup/test-jdbc.jar" "$DB_OWNER_USER" "$DB_OWNER_PASSWORD" "$DB_URL"

# Install libsigar - library used in report-scheduler to monitor free RAM
cp "$SCRIPTS_DIR/setup/libsigar-amd64-linux.so" /usr/lib

# Add rules for sudo into /etc/sudoers for integration-scheduler:
echo "integration-scheduler ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/integration-scheduler
chmod 440 /etc/sudoers.d/integration-scheduler

# Install services for this instance
"$SCRIPTS_DIR/install-daemon-service.sh" "$WEBSITE" services "$VERSION" "${DB_OWNER_USER}/${DB_OWNER_PASSWORD}@$DB_URL" \
    "${DB_OWNER_USER}_user/${DB_USER_PASSWORD}@$DB_URL" "${DB_OWNER_USER}_rpt/${DB_RPT_PASSWORD}@$DB_URL"
"$SCRIPTS_DIR/install-daemon-service.sh" "$WEBSITE" integration-scheduler "$VERSION" "${DB_OWNER_USER}/${DB_OWNER_PASSWORD}@$DB_URL"
"$SCRIPTS_DIR/install-cron-service.sh" "$WEBSITE" syncs3 "$VERSION" "0 3 * * *" "${DB_OWNER_USER}/${DB_OWNER_PASSWORD}@$DB_URL"

if [ -n "$MONITORING_VERSION" ]; then
    "$SCRIPTS_DIR/install-monitor-service.sh" "$MONITORING_VERSION" "$DB_OWNER_USER" "$DB_MONITOR_USER" "$DB_MONITOR_PASSWORD" "$DB_URL" "$AES_PASSWORD"
fi

# Set AES password if specified
if [ -n "$AES_PASSWORD" ]; then
    export CREDENTIALS_CONF
    CREDENTIALS_CONF="$SCRIPTS_DIR/credentials.conf"

    # shellcheck source=../../utils.sh
    . "$SCRIPTS_DIR/utils.sh"

    config_service_env "$WEBSITE" "services"
    echo "aesPassword=$AES_PASSWORD" > "$SERVICE_PATH/ov.properties"
    config_service_env "$WEBSITE" "integration-scheduler"
    echo "aesPassword=$AES_PASSWORD" > "$SERVICE_PATH/ov.properties"
fi

# Start up services
systemctl start "${WEBSITE}_services"
systemctl start "${WEBSITE}_integration-scheduler"

if [ -n "$MONITORING_VERSION" ]; then
    systemctl start "monitoring"
fi

# Finished
echo "Application server setup complete."