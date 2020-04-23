#!/bin/bash

function usage() {
    echo "### Script for uninstall website from Tomcat ###"
    echo "Usage: $(basename "$0") <website>"
}

if [ "$#" -ne 1 ]; then
    usage
    exit 1
fi

# shellcheck source=utils.sh
. "$(dirname "$0")/utils.sh"

require_root_user

WEBSITE=$1

SERVER_XML_FILE="$TOMCAT_PATH/conf/server.xml"
CONTEXT_XML_FILE="$TOMCAT_PATH/conf/Catalina/$WEBSITE/ROOT.xml"

ENGINE_XPATH="Service/Engine[@name=\"Catalina\"]"
HOST_XPATH="Host[@name=\"$WEBSITE\"]"
FULL_HOST_XPATH="$ENGINE_XPATH/$HOST_XPATH"

APP_BASE="$(read_xml_value "$SERVER_XML_FILE" "$FULL_HOST_XPATH" "appBase")"
if [ -z "$APP_BASE" ]; then
    echo "No website with name [$WEBSITE] is available!"
    exit 1
fi

APP_BASE_PATH="$TOMCAT_PATH/$APP_BASE"
CONTEXT_PATH="$TOMCAT_PATH/conf/Catalina/$WEBSITE"
PROPERTIES_PATH="$TOMCAT_PATH/$WEBSITE"

# Stop Tomcat
START_TOMCAT=0
if is_daemon_running "$TOMCAT_SERVICE"; then
    echo "Stopping Tomcat..."
    systemctl stop "$TOMCAT_SERVICE" || exit 1

    START_TOMCAT=1
fi

test -d "$APP_BASE_PATH" && (rm -rf "$APP_BASE_PATH" || exit 1)
test -d "$CONTEXT_PATH" && (rm -rf "$CONTEXT_PATH" || exit 1)
test -d "$PROPERTIES_PATH" && (rm -rf "$PROPERTIES_PATH" || exit 1)

"$(dirname "$0")/setup/delete-xml-node.py" "$SERVER_XML_FILE" "$ENGINE_XPATH" "$HOST_XPATH" || exit 1

if [ "$START_TOMCAT" -eq 1 ]; then
    echo "Starting Tomcat..."
    systemctl start "$TOMCAT_SERVICE" || exit 1
fi
