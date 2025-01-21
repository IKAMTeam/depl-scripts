#!/bin/bash
function usage() {
    echo "### Script to download com.onevizion artifact from Maven repository ###"
    echo "Usage: $(basename "$0") <artifact> [target_file]"
    echo " "
    echo "Examples:"
    echo "$(basename "$0") db:1.0"
    echo "$(basename "$0") report-scheduler:1.0:jar:shaded"
    echo "$(basename "$0") web:1.0:war"
    echo "$(basename "$0") web:1.0:war web.war"
    echo "$(basename "$0") web:1.0:war:tomcat10 web.war"
}

if [ "$#" -lt 1 ]; then
    usage
    exit 1
fi

# shellcheck source=utils.sh
. "$(dirname "$0")/utils.sh"

MVN_ARTIFACT="$1" # report-scheduler:1.0-SNAPSHOT:jar:shaded
TARGET_PATH="$2"

ARTIFACT_ID="$(echo "$MVN_ARTIFACT" | awk -F ':' '{print $1}')" # report-scheduler
VERSION="$(echo "$MVN_ARTIFACT" | awk -F ':' '{print $2}')" # 1.0-SNAPSHOT
PACKAGING="$(echo "$MVN_ARTIFACT" | awk -F ':' '{print $3}')" # jar
ARTIFACT_CLASSIFIER="$(echo "$MVN_ARTIFACT" | awk -F ':' '{print $4}')" # shaded

if [ -z "$PACKAGING" ]; then
  PACKAGING="jar"
fi
if [ -z "$TARGET_PATH" ]; then
  TARGET_PATH="${ARTIFACT_ID}.${PACKAGING}"
fi

download_artifact "com.onevizion" "$ARTIFACT_ID" "$VERSION" "$PACKAGING" "$ARTIFACT_CLASSIFIER" "$TARGET_PATH" || exit 1
