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

eval "$CONFIG_DATA"

set -o errexit
set -o pipefail

init_credentials

# Update timezone to EST
ln -sf /usr/share/zoneinfo/US/Eastern /etc/localtime

# Install libsigar - library used in report-scheduler to monitor free RAM
cp "$SCRIPTS_PATH/setup/libsigar-amd64-linux.so" /usr/lib

# Add rules for sudo into /etc/sudoers for integration-scheduler:
echo "integration-scheduler ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/integration-scheduler
chmod 440 /etc/sudoers.d/integration-scheduler

# Install services for this instance
"$SCRIPTS_PATH/install-daemon-service.sh" "$WEBSITE" services "$VERSION" --aes-password "$AES_PASSWORD" "${DB_OWNER_USER}/${DB_OWNER_PASSWORD}@$DB_URL" \
    "${DB_OWNER_USER}_user/${DB_USER_PASSWORD}@$DB_URL" "${DB_OWNER_USER}_rpt/${DB_RPT_PASSWORD}@$DB_URL"
"$SCRIPTS_PATH/install-daemon-service.sh" "$WEBSITE" integration-scheduler "$VERSION" --aes-password "$AES_PASSWORD" "${DB_OWNER_USER}/${DB_OWNER_PASSWORD}@$DB_URL"
"$SCRIPTS_PATH/install-cron-service.sh" "$WEBSITE" syncs3 "$VERSION" --aes-password "$AES_PASSWORD" "0 3 * * *" "${DB_OWNER_USER}/${DB_OWNER_PASSWORD}@$DB_URL"

if [ -n "$MONITORING_VERSION" ]; then
    "$SCRIPTS_PATH/install-monitor-service.sh" "$MONITORING_VERSION" "$DB_OWNER_USER" "$DB_MONITOR_USER" "$DB_MONITOR_PASSWORD" "$DB_URL" "$AES_PASSWORD"

    require_credentials
    config_service_env "" "monitoring"
    MONITOR_XML="$SERVICE_PATH/db-schemas.xml"

    if [ -n "$MONITOR_AWS_SQS_ACCESS_KEY" ] && [ -n "$MONITOR_AWS_SQS_SECRET_KEY" ] && [ -n "$MONITOR_AWS_SQS_QUEUE_URL" ]; then
        "$SCRIPTS_PATH/setup/insert-xml-node.py" "$MONITOR_XML" "$SCRIPTS_PATH/setup/templates/monitor-aws-sqs.template" ''
        "$SCRIPTS_PATH/setup/update-xml-value.py" "$MONITOR_XML" 'aws-sqs/sqs/access-key' '' "$MONITOR_AWS_SQS_ACCESS_KEY"
        "$SCRIPTS_PATH/setup/update-xml-value.py" "$MONITOR_XML" 'aws-sqs/sqs/secret-key' '' "$MONITOR_AWS_SQS_SECRET_KEY"
        "$SCRIPTS_PATH/setup/update-xml-value.py" "$MONITOR_XML" 'aws-sqs/sqs/queue-url' '' "$MONITOR_AWS_SQS_QUEUE_URL"
    fi

    "$SCRIPTS_PATH/setup/update-xml-value.py" "$MONITOR_XML" 'error-email/host' '' "$MONITOR_ERROR_MAIL_HOST"
    "$SCRIPTS_PATH/setup/update-xml-value.py" "$MONITOR_XML" 'error-email/port' '' "$MONITOR_ERROR_MAIL_PORT"
    "$SCRIPTS_PATH/setup/update-xml-value.py" "$MONITOR_XML" 'error-email/username' '' "$MONITOR_ERROR_MAIL_USERNAME"
    "$SCRIPTS_PATH/setup/update-xml-value.py" "$MONITOR_XML" 'error-email/password' '' "$MONITOR_ERROR_MAIL_PASSWORD"
    "$SCRIPTS_PATH/setup/update-xml-value.py" "$MONITOR_XML" 'error-email/from' '' "$MONITOR_ERROR_MAIL_FROM"
    "$SCRIPTS_PATH/setup/update-xml-value.py" "$MONITOR_XML" 'error-email/to' '' "$MONITOR_ERROR_MAIL_TO"

    "$SCRIPTS_PATH/setup/update-xml-value.py" "$MONITOR_XML" 'warning-email/host' '' "$MONITOR_WARN_MAIL_HOST"
    "$SCRIPTS_PATH/setup/update-xml-value.py" "$MONITOR_XML" 'warning-email/port' '' "$MONITOR_WARN_MAIL_PORT"
    "$SCRIPTS_PATH/setup/update-xml-value.py" "$MONITOR_XML" 'warning-email/username' '' "$MONITOR_WARN_MAIL_USERNAME"
    "$SCRIPTS_PATH/setup/update-xml-value.py" "$MONITOR_XML" 'warning-email/password' '' "$MONITOR_WARN_MAIL_PASSWORD"
    "$SCRIPTS_PATH/setup/update-xml-value.py" "$MONITOR_XML" 'warning-email/from' '' "$MONITOR_WARN_MAIL_FROM"
    "$SCRIPTS_PATH/setup/update-xml-value.py" "$MONITOR_XML" 'warning-email/to' '' "$MONITOR_WARN_MAIL_TO"
fi

# Start up services
systemctl start "${WEBSITE}_services"
systemctl start "${WEBSITE}_integration-scheduler"

if [ -n "$MONITORING_VERSION" ]; then
    systemctl start "monitoring"
fi

# Finished
echo "Application server setup complete."
