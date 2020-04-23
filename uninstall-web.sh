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

START_TOMCAT=0
if is_daemon_running "$TOMCAT_SERVICE"; then
    echo "Stopping Tomcat..."
    systemctl stop "$TOMCAT_SERVICE" || exit 1

    START_TOMCAT=1
fi

SERVER_XML_FILE="$TOMCAT_PATH/conf/server.xml"
CONTEXT_XML_FILE="$TOMCAT_PATH/conf/Catalina/$WEBSITE/ROOT.xml"

ENGINE_XPATH="Service/Engine[@name=\"Catalina\"]"
HOST_XPATH="Host[@name=\"$WEBSITE\"]"
FULL_HOST_XPATH="$ENGINE_XPATH/$HOST_XPATH"

APP_BASE_PATH="$TOMCAT_PATH/$(read_xml_value "$SERVER_XML_FILE" "$FULL_HOST_XPATH" "appBase")"
DOC_BASE_PATH="$(read_xml_value "$CONTEXT_XML_FILE" "" "docBase")"
CONTEXT_PATH="$TOMCAT_PATH/conf/Catalina/$WEBSITE"
PROPERTIES_PATH="$TOMCAT_PATH/$WEBSITE"

# Expand catalina.home
# shellcheck disable=SC2016
CATALINA_HOME_VAR='${catalina.home}'
DOC_BASE_PATH="${DOC_BASE_PATH//$CATALINA_HOME_VAR/$TOMCAT_PATH}"

echo "$APP_BASE_PATH"
echo "$DOC_BASE_PATH"
echo "$CONTEXT_PATH"
echo "$PROPERTIES_PATH"

(test -d "$APP_BASE_PATH" && rm -rf "$APP_BASE_PATH") || exit 1
(test -d "$DOC_BASE_PATH" && rm -rf "$DOC_BASE_PATH") || exit 1
(test -d "$CONTEXT_PATH" && rm -rf "$CONTEXT_PATH") || exit 1
(test -d "$PROPERTIES_PATH" && rm -rf "$PROPERTIES_PATH") || exit 1

echo debug

"$(dirname "$0")/setup/delete-xml-node.py" "$SERVER_XML_FILE" "$ENGINE_XPATH" "$HOST_XPATH" || exit 1

if [ "$START_TOMCAT" -eq 1 ]; then
    echo "Starting Tomcat..."
    systemctl start "$TOMCAT_SERVICE" || exit 1
fi
