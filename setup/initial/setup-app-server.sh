#!/bin/bash

function usage() {
    echo "### This script will automatically set up the services needed to run on the app server ###"
    echo "Before run this script you need to install Java 11 and Git on server"
    echo " "
    echo "Usage: $(basename "$0") <config file>"
    echo " "
    echo "Example: $(basename "$0") setup-app-server.conf"
}

if [ "$#" -ne 1 ]; then
    usage
    exit 1
fi

# shellcheck source=utils.sh
. "$(dirname "$0")/utils.sh"

require_root_user

# TODO: import config

set -o errexit
set -o pipefail
set -o nounset

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
"$SCRIPTS_DIR/install-monitoring-service.sh" "$MONITORING_VERSION" "$DB_OWNER_USER" "$DB_MONITOR_USER" "$DB_MONITOR_PASSWORD" "$AES_PASSWORD"

# Start up services
systemctl start "${WEBSITE}_services"
systemctl start "${WEBSITE}_integration-scheduler"
systemctl start "monitoring"

# Finished
echo "Application server setup is complete."
