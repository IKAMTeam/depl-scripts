#!/bin/bash
if [ "$#" -ne 3 ]; then
    echo "### Script for initial download OneVizion web application ###"
    echo "Usage: $(basename "$0") <version> <tomcat path> <target webapp directory name>"
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

delete_on_exit "$DOWNLOAD_PATH"
download_artifact "$ARTIFACT" "$VERSION" "$DOWNLOAD_PATH" || exit 1

echo "Unpacking WAR [$DOWNLOAD_PATH] to [$WEBAPP_PATH]..."
unpack_ps_war "$WEBAPP_PATH" "$DOWNLOAD_PATH" || exit 1
