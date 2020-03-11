#!/bin/bash

function usage() {
    echo "### This script will automatically set up the services needed to run on the web server ###"
    echo "Before run this script you need to install Java 11, Tomcat 8.5 and Git on server"
    echo " "
    echo "Usage: $(basename "$0") <config file>"
    echo " "
    echo "Example: $(basename "$0") setup-web-server.conf"
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

# Update depl-scripts
checkout_depl_scripts

# Test database connection
java -jar "$SCRIPTS_DIR/setup/test-jdbc.jar" "$DB_OWNER_USER" "$DB_OWNER_PASSWORD" "$DB_URL"

# Setup timeout for Tomcat shutdown process before it will be killed
sed -i 's/# SHUTDOWN_WAIT="30"/SHUTDOWN_WAIT="30"/g' "$TOMCAT_DIR/conf/tomcat.conf"

# Enable Tomcat service to start at boot time
systemctl enable tomcat

# Copy configuration template
cp -rf "$SCRIPTS_DIR"/setup/tomcat/conf/* "$TOMCAT_DIR/conf"
chown -R "$TOMCAT_OWNER" "$TOMCAT_DIR/conf/Catalina/sitename.onevizion.com"
cp -rf "$SCRIPTS_DIR"/setup/tomcat/webapps/* "$TOMCAT_DIR/webapps"
rm -f "$TOMCAT_DIR/conf/tomcat-users.xml"

# Configure Tomcat filesystem permissions
"$SCRIPTS_DIR/config-tomcat-security.sh" "$TOMCAT_DIR"

# Set up the config files and replace values as appropriate
sed -i -- "s/sitename.onevizion.com/$WEBSITE/g" "$TOMCAT_DIR/conf/server.xml"
mv "$TOMCAT_DIR/conf/Catalina/sitename.onevizion.com" "$TOMCAT_DIR/conf/Catalina/$WEBSITE"

CONFIG_FILE="$TOMCAT_DIR/conf/Catalina/$WEBSITE/ROOT.xml"

sed -i -- "s/[placeholder for Oracle host]:[placeholder for Oracle port]:[placeholder for Oracle SID]/$DB_URL/g" "$CONFIG_FILE"
sed -i -- "s/[placeholder username for OWNER schema]/$DB_OWNER_USER/g" "$CONFIG_FILE"
sed -i -- "s/[placeholder for OWNER schema password]/$DB_OWNER_PASSWORD/g" "$CONFIG_FILE"
sed -i -- "s/[placeholder username for USER schema]/${DB_OWNER_USER}_USER/g" "$CONFIG_FILE"
sed -i -- "s/[placeholder for USER schema password]/$DB_USER_PASSWORD/g" "$CONFIG_FILE"
sed -i -- "s/[placeholder username for PKG schema]/${DB_OWNER_USER}_PKG/g" "$CONFIG_FILE"
sed -i -- "s/[placeholder for PKG schema password]/$DB_PKG_PASSWORD/g" "$CONFIG_FILE"
sed -i -- "s/[placeholder for error reports email subject]/$ERROR_REPORTS_SUBJECT/g" "$CONFIG_FILE"

# TODO: run ps-web
"$SCRIPTS_DIR/update-ps-web.sh" ${_VERSION} ${_TOMCAT_DIR} ps

# Finished
echo "Web server setup is complete."
