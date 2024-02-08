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

if [ -n "$3" ] && { [ "$3" == "-f" ] || [ "$3" == "--force" ]; }; then
    FORCE_UPDATE="1"
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
    # shellcheck disable=SC2153
    SERVICE_PATH="$SERVICES_PATH/$SERVICE_NAME"

    if ! is_snapshot_version "$NEW_VERSION" && [ "$FORCE_UPDATE" != "1" ]; then
        ARTIFACT_JAR="${ARTIFACT}.jar"
        ARTIFACT_VERSION="$(extract_and_read_artifact_version "$SERVICE_PATH/$ARTIFACT_JAR")"

        if [ "$ARTIFACT_VERSION" == "$NEW_VERSION" ]; then
            # Skip service
            echo "[$ARTIFACT $NEW_VERSION] is already installed for website [$WEBSITE]!"
            continue
        fi
    fi

    SERVICE_NAMES_TO_UPDATE+=("$SERVICE_NAME")
done

if [ "${#SERVICE_NAMES_TO_UPDATE[@]}" -eq 0 ]; then
    echo "No any services for website [$MATCH_WEBSITE] to update"
    exit 0
fi

for SERVICE_NAME in "${SERVICE_NAMES_TO_UPDATE[@]}"; do
    ARTIFACT="$(get_artifact_name "$SERVICE_NAME")"
    # shellcheck disable=SC2153
    SERVICE_PATH="$SERVICES_PATH/$SERVICE_NAME"

    echo "Deploying [$ARTIFACT $NEW_VERSION] at"
    printf '%s\n' "$SERVICE_PATH"

    # Will export next variables: REPORT_EXEC_DOWNLOAD_PATH, EXPORT_EXEC_DOWNLOAD_PATH, DOWNLOAD_PATH
    download_service_artifacts "$ARTIFACT" "$NEW_VERSION" || exit 1

    echo "Updating [$SERVICE_NAME] at [$SERVICE_PATH]..."

    if is_daemon_running "$SERVICE_NAME"; then
        echo "Stopping [$SERVICE_NAME]..."
        systemctl stop "$SERVICE_NAME"
    fi

    copy_service_artifacts "$ARTIFACT" || exit 1

    if is_daemon_installed "$SERVICE_NAME"; then
        extract_launcher_script "$ARTIFACT" || exit 1

        echo "Starting [$SERVICE_NAME]..."
        systemctl start "$SERVICE_NAME" || exit $?
    elif is_cron_installed "$SERVICE_NAME"; then
        extract_cron_launcher_script "$ARTIFACT" || exit 1
    fi
done