#!/bin/bash
if [ "$#" -ne 3 ]; then
    echo "### Script for update existing OneVizion web application to another version ###"
    echo "Usage: $(basename "$0") <version> <tomcat path> <webapp directory name>"
    echo " "
    echo "Example: $(basename "$0") 1.0 /opt/tomcat sitename.onevizion.com"
    exit 1
fi

# shellcheck source=utils.sh
. "$(dirname "$0")/utils.sh"

require_root_user

ARTIFACT=ps-web

VERSION=$1
TOMCAT_PATH=$2
WEBAPP_DIRNAME=$3

WEBAPP_PATH="$TOMCAT_PATH/$WEBAPP_DIRNAME"
DOWNLOAD_PATH="$(mktemp --suffix="_ps-web")"

echo "Deploying [$ARTIFACT $VERSION] at [$WEBAPP_PATH]..."

download_artifact "$ARTIFACT" "$VERSION" "$DOWNLOAD_PATH" || exit 1
delete_on_exit "$DOWNLOAD_PATH"

# Prevent script fail if Tomcat is not running
echo "Stopping Tomcat..."
systemctl stop "$TOMCAT_SERVICE" || exit 1

echo "Deploying WAR [$DOWNLOAD_PATH] to [$WEBAPP_PATH]..."
unpack_ps_war "$WEBAPP_PATH" "$DOWNLOAD_PATH" || exit 1
cleanup_tomcat "$TOMCAT_PATH"

sleep 5s

# Check is Tomcat already alive by user $TOMCAT_UN and process name "java"
function get_tomcat_pid() {
    netstat -elp | grep -m 1 -P "$TOMCAT_UN".+?java | awk '{ print $NF } ' | cut -d"/" -f1
}

TOMCAT_PID=$(get_tomcat_pid)
if [ -n "$TOMCAT_PID" ]; then
    echo "Tomcat didn't stop in time, kill $TOMCAT_PID"
    kill "$TOMCAT_PID"
    sleep 30s
    
    TOMCAT_PID=$(get_tomcat_pid)
    if [ -n "$TOMCAT_PID" ]; then
        echo "Can't stop Tomcat" >&2
        exit 1
    fi
fi

echo "Starting Tomcat..."
systemctl start "$TOMCAT_SERVICE" || exit 1

if ! wait_log "$TOMCAT_PATH/logs/$TOMCAT_WAIT_LOG" "Server startup in" "SEVERE" 10m; then
    exit 1
fi
