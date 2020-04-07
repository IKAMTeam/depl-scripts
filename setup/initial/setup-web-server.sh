#!/bin/bash

function usage() {
    echo "### This script will automatically set up the services needed to run on the web server ###"
    echo "Before run this script you need to install Python 2.7, Java 11, Tomcat 8.5 on server"
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

# Setup timeout for Tomcat shutdown process before it will be killed
if [ -f "$TOMCAT_PATH/conf/tomcat.conf" ]; then
    sed -i 's/# SHUTDOWN_WAIT="30"/SHUTDOWN_WAIT="30"/g' "$TOMCAT_PATH/conf/tomcat.conf"
fi

# Configure Auto-Restart for Tomcat if it will be crashed
grep 'Restart=' /usr/lib/systemd/system/tomcat.service &>/dev/null ||
    sed -i 's/\[Service\]/[Service]\nRestart=on-failure\nRestartSec=5s/g' /usr/lib/systemd/system/tomcat.service
systemctl daemon-reload

# Enable Tomcat service to start at boot time
systemctl enable "$TOMCAT_SERVICE"

# Copy configuration template
if grep 'server="ov"' "$TOMCAT_PATH/conf/server.xml" &>/dev/null; then
    # Ignore server.xml from match files to copy
    GLOBIGNORE="$SCRIPTS_PATH/setup/tomcat/conf/server.xml"
fi

cp -rf "$SCRIPTS_PATH"/setup/tomcat/conf/* "$TOMCAT_PATH/conf"
cp -rf "$SCRIPTS_PATH"/setup/tomcat/webapps/* "$TOMCAT_PATH/webapps"
GLOBIGNORE=''

rm -f "$TOMCAT_PATH/conf/tomcat-users.xml"

# Configure Tomcat filesystem permissions
"$SCRIPTS_PATH/config-tomcat-security.sh" "$TOMCAT_PATH"

# Install web
"$SCRIPTS_PATH/install-web.sh" "$WEBSITE" "$VERSION" "$DB_OWNER_USER" "$DB_OWNER_PASSWORD" "$DB_USER_PASSWORD" \
    "$DB_PKG_PASSWORD" "$DB_URL" "$TOMCAT_PATH" "$ENTERPRISE_EDITION" "$AES_PASSWORD"

# Finished
echo "Web server setup complete."
