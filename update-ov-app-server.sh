#!/bin/bash

function usage() {
    echo "### Script to update all services for specified website ###"
    echo "Usage: $(basename "$0") <website> <new version> [-f/--force]"
}

if [ "$#" -lt 2 ]; then
    usage
    exit 1
fi

# shellcheck source=utils.sh
. "$(dirname "$0")/utils.sh"

require_root_user

MATCH_WEBSITE=$1
NEW_VERSION=$2

FORCE_UPDATE_ARG=""
if [ -n "$3" ] && { [ "$3" == "-f" ] || [ "$3" == "--force" ]; }; then
    FORCE_UPDATE_ARG="--force"
fi

mapfile -t ALL_SERVICE_NAMES < <("$(dirname "$0")/list-services.sh" --short-format)
SERVICE_NAMES_TO_UPDATE=()

for SERVICE_NAME in "${ALL_SERVICE_NAMES[@]}"; do
    WEBSITE="$(get_website_name "$SERVICE_NAME")"
    if [ "$WEBSITE" != "$MATCH_WEBSITE" ]; then
        # Skip service
        continue
    fi

    ARTIFACT="$(get_artifact_name "$SERVICE_NAME")"
    ARTIFACT_JAR="${ARTIFACT}.jar"

    # shellcheck disable=SC2153
    SERVICE_PATH="$SERVICES_PATH/$SERVICE_NAME"

    if [ ! -f "$SERVICE_PATH/$ARTIFACT_JAR" ]; then
        # Python services are not supported
        continue
    fi

    if ! is_snapshot_version "$NEW_VERSION" && [ "$FORCE_UPDATE_ARG" != "--force" ]; then
        ARTIFACT_VERSION="$(extract_and_read_artifact_version "$SERVICE_PATH/$ARTIFACT_JAR")"

        if [ "$ARTIFACT_VERSION" == "$NEW_VERSION" ]; then
            # Skip service
            echo
            echo "[$ARTIFACT $NEW_VERSION] is already installed for website [$WEBSITE]!"
            continue
        fi
    fi

    SERVICE_NAMES_TO_UPDATE+=("$SERVICE_NAME")
done

if [ "${#SERVICE_NAMES_TO_UPDATE[@]}" -eq 0 ]; then
    echo "No services found for website [$MATCH_WEBSITE]"
    exit 0
fi

for SERVICE_NAME in "${SERVICE_NAMES_TO_UPDATE[@]}"; do
    ARTIFACT="$(get_artifact_name "$SERVICE_NAME")"

    echo
    "$(dirname "$0")/update-ov.sh" "$MATCH_WEBSITE" "$ARTIFACT" "$NEW_VERSION" "$FORCE_UPDATE_ARG" || exit 1
done
