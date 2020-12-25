#!/bin/bash
function usage() {
    echo "### Script for initial download OneVizion web application ###"
    echo "Usage: $(basename "$0") <version> <target webapp directory name>"
    echo " "
    echo "Example: $(basename "$0") 1.0 sitename.onevizion.com"
}

if [ "$#" -ne 2 ]; then
    usage
    exit 1
fi

# shellcheck source=utils.sh
. "$(dirname "$0")/utils.sh"

require_root_user

GROUP_ID=com.onevizion
ARTIFACT_ID=ps-web
PACKAGING=war
REPOSITORY_URL="$RELEASES_REPO_URL,$SNAPSHOT_REPO_URL"
DOWNLOAD_SUFFIX=.war

VERSION=$1
WEBAPP_DIRNAME=$2

WEBAPP_PATH="$TOMCAT_PATH/$WEBAPP_DIRNAME"
DOWNLOAD_PATH="$(mktemp --suffix="_ps-web")"

delete_on_exit "$DOWNLOAD_PATH"
download_artifact "$GROUP_ID" "$ARTIFACT_ID" "$VERSION" "$PACKAGING" "$REPOSITORY_URL" "$DOWNLOAD_PATH" "$DOWNLOAD_SUFFIX" || exit 1

echo "Unpacking WAR [$DOWNLOAD_PATH] to [$WEBAPP_PATH]..."
unpack_ps_war "$WEBAPP_PATH" "$DOWNLOAD_PATH" || exit 1
