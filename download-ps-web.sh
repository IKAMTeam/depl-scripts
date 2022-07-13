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
ARTIFACT_ID=web
ARTIFACT_ID_OLD=ps-web
PACKAGING=war
ARTIFACT_CLASSIFIER=""

VERSION=$1
WEBAPP_DIRNAME=$2

WEBAPP_PATH="$TOMCAT_PATH/$WEBAPP_DIRNAME"
DOWNLOAD_PATH="$(mktemp --suffix="_web")"

delete_on_exit "$DOWNLOAD_PATH"
if ! download_artifact "$GROUP_ID" "$ARTIFACT_ID" "$VERSION" "$PACKAGING" "$ARTIFACT_CLASSIFIER" "$DOWNLOAD_PATH"; then
    echo "Fallback to download artifact using old name [$ARTIFACT_ID_OLD]"
    download_artifact "$GROUP_ID" "$ARTIFACT_ID_OLD" "$VERSION" "$PACKAGING" "$ARTIFACT_CLASSIFIER" "$DOWNLOAD_PATH" || exit 1
fi

echo "Unpacking WAR [$DOWNLOAD_PATH] to [$WEBAPP_PATH]..."
extract_war_contents "$WEBAPP_PATH" "$DOWNLOAD_PATH" || exit 1
