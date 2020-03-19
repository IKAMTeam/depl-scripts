#!/bin/bash

function usage() {
    echo "### This script will automatically set up the services needed to run on the web server ###"
    echo "Before run this script you need to install Python 2.7, Java 11, Tomcat 8.5 on server"
    echo " "
    echo "Usage: $(basename "$0") <config file>"
    echo " "
    echo "Example: $(basename "$0") setup-web-server.conf"
}

if [ "$#" -ne 1 ]; then
    usage
    exit 1
fi

# shellcheck source=setup-utils.sh
. "$(dirname "$0")/setup-utils.sh"

require_root_user

CONFIG_FILE="$1"

# shellcheck source=setup-web-server.conf.template
. "$CONFIG_FILE"

set -o errexit
set -o pipefail

init_credentials

# Update timezone to EST
ln -sf /usr/share/zoneinfo/US/Eastern /etc/localtime

# Test database connection
java -jar "$SCRIPTS_DIR/setup/test-jdbc.jar" "$DB_OWNER_USER" "$DB_OWNER_PASSWORD" "$DB_URL"

# Setup timeout for Tomcat shutdown process before it will be killed
if [ -f "$TOMCAT_DIR/conf/tomcat.conf" ]; then
    sed -i 's/# SHUTDOWN_WAIT="30"/SHUTDOWN_WAIT="30"/g' "$TOMCAT_DIR/conf/tomcat.conf"
fi

# Configure Auto-Restart for Tomcat if it will be crashed
sed -i 's/\[Service\]/[Service]\nRestart=on-failure\nRestartSec=5s/g' /usr/lib/systemd/system/tomcat.service
systemctl daemon-reload

# Enable Tomcat service to start at boot time
systemctl enable "$TOMCAT_SERVICE"

# Copy configuration template
cp -rf "$SCRIPTS_DIR"/setup/tomcat/conf/* "$TOMCAT_DIR/conf"
cp -rf "$SCRIPTS_DIR"/setup/tomcat/webapps/* "$TOMCAT_DIR/webapps"
rm -f "$TOMCAT_DIR/conf/tomcat-users.xml"

# Configure Tomcat filesystem permissions
"$SCRIPTS_DIR/config-tomcat-security.sh" "$TOMCAT_DIR"

# Set up the config files and replace values as appropriate
mv "$TOMCAT_DIR/conf/Catalina/sitename.onevizion.com" "$TOMCAT_DIR/conf/Catalina/$WEBSITE"

"$(dirname "$0")/update-xml-value.py" "$TOMCAT_DIR/conf/server.xml" 'Service/Engine/Host[@name="sitename.onevizion.com"]' \
    appBase "$WEBSITE-webapp"
"$(dirname "$0")/update-xml-value.py" "$TOMCAT_DIR/conf/server.xml" 'Service/Engine/Host[@name="sitename.onevizion.com"]' \
    name "$WEBSITE"

CONTEXT_XML_FILE="$TOMCAT_DIR/conf/Catalina/$WEBSITE/ROOT.xml"

"$(dirname "$0")/update-xml-value.py" "$CONTEXT_XML_FILE" '' docBase "\${catalina.home}/$WEBSITE-webapp"
"$(dirname "$0")/update-xml-value.py" "$CONTEXT_XML_FILE" 'Parameter[@name="app.serverUrl"]' value "$WEBSITE"
"$(dirname "$0")/update-xml-value.py" "$CONTEXT_XML_FILE" 'Parameter[@name="web.dbSid"]' value "$DB_URL"
"$(dirname "$0")/update-xml-value.py" "$CONTEXT_XML_FILE" 'Parameter[@name="web.dbOwner"]' value "$DB_OWNER_USER"
"$(dirname "$0")/update-xml-value.py" "$CONTEXT_XML_FILE" 'Parameter[@name="web.dbOwnerPassword"]' value "$DB_OWNER_PASSWORD"
"$(dirname "$0")/update-xml-value.py" "$CONTEXT_XML_FILE" 'Parameter[@name="web.dbUser"]' value "${DB_OWNER_USER}_user"
"$(dirname "$0")/update-xml-value.py" "$CONTEXT_XML_FILE" 'Parameter[@name="web.dbUserPassword"]' value "$DB_USER_PASSWORD"
"$(dirname "$0")/update-xml-value.py" "$CONTEXT_XML_FILE" 'Parameter[@name="web.dbPkg"]' value "${DB_OWNER_USER}_pkg"
"$(dirname "$0")/update-xml-value.py" "$CONTEXT_XML_FILE" 'Parameter[@name="web.dbPkgPassword"]' value "$DB_PKG_PASSWORD"
"$(dirname "$0")/update-xml-value.py" "$CONTEXT_XML_FILE" 'Parameter[@name="app.serverUrl"]' value "https://$WEBSITE"
"$(dirname "$0")/update-xml-value.py" "$CONTEXT_XML_FILE" 'Parameter[@name="web.enterpriseEdition"]' value "$ENTERPRISE_EDITION"

# Set AES password if specified
if [ -n "$AES_PASSWORD" ]; then
    mkdir -p "$TOMCAT_DIR/$WEBSITE"
    echo "aesPassword=$AES_PASSWORD" > "$TOMCAT_DIR/$WEBSITE/ov.properties"
fi

"$SCRIPTS_DIR/update-ps-web.sh" "$VERSION" "$TOMCAT_DIR" "$WEBSITE-webapp"

# Finished
echo "Web server setup complete."
