#!/bin/bash
if [ "$#" -ne 3 ]; then
    echo "### Script for update web/services artifacts ###"
    echo "Usage: $(basename "$0") <artifact> <website> <new version>"
    echo "Usage: $(basename "$0") tomcat <webapp directory name> <new version>"
    exit 1
fi

# shellcheck source=utils.sh
. "$(dirname "$0")/utils.sh"

require_root_user

if [ "$1" == "tomcat" ]; then
    ARTIFACT=ps-web
    WEBAPP_DIRNAME=$2
    VERSION=$3

    WEBAPP_PATH="$TOMCAT_PATH/$WEBAPP_DIRNAME"
    DOWNLOAD_PATH="$(mktemp --suffix="_ps-web")"

    echo "Deploying [$ARTIFACT $VERSION] at [$WEBAPP_PATH]..."

    delete_on_exit "$DOWNLOAD_PATH"
    download_artifact "$ARTIFACT" "$VERSION" "$DOWNLOAD_PATH" || exit 1

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
else
    MATCH_ARTIFACT=$1
    MATCH_WEBSITE=$2
    NEW_VERSION=$3

    export SERVICE_UN="$MATCH_ARTIFACT"
    export SERVICE_GROUP="$MATCH_ARTIFACT"

    export SERVICE_NAME
    export SERVICE_PATH

    mapfile -t ALL_SERVICE_NAMES < <("$(dirname "$0")/list-services.sh" --short-format)
    SERVICE_NAMES_FOR_UPDATE=()
    SERVICE_PATHS_FOR_UPDATE=()

    for SERVICE_NAME in "${ALL_SERVICE_NAMES[@]}"; do
        ARTIFACT="$(get_artifact_name "$SERVICE_NAME")"
        if [ "$ARTIFACT" != "$MATCH_ARTIFACT" ]; then
            # Skip service
            continue
        fi

        WEBSITE="$(get_website_name "$SERVICE_NAME")"
        if [ "$WEBSITE" != "$MATCH_WEBSITE" ]; then
            # Skip service
            continue
        fi

        # shellcheck disable=SC2153
        SERVICE_PATH="$SERVICES_PATH/$SERVICE_NAME"

        SERVICE_NAMES_FOR_UPDATE+=("$SERVICE_NAME")
        SERVICE_PATHS_FOR_UPDATE+=("$SERVICE_PATH")
    done

    if [ "${#SERVICE_NAMES_FOR_UPDATE[@]}" -eq 0 ]; then
        echo "No [$MATCH_ARTIFACT] for website [$MATCH_WEBSITE] for update"
        exit 1
    fi

    echo "Deploying [$MATCH_ARTIFACT $NEW_VERSION] at"
    printf '%s\n' "${SERVICE_PATHS_FOR_UPDATE[@]}"

    # Will export next variables: REPORT_EXEC_DOWNLOAD_PATH, EXPORT_EXEC_DOWNLOAD_PATH, DOWNLOAD_PATH
    download_service_artifacts "$MATCH_ARTIFACT" "$NEW_VERSION" || exit 1

    for SERVICE_NAME in "${SERVICE_NAMES_FOR_UPDATE[@]}"; do
        # shellcheck disable=SC2153
        SERVICE_PATH="$SERVICES_PATH/$SERVICE_NAME"

        echo "Updating [$SERVICE_NAME] at [$SERVICE_PATH]..."

        if is_daemon_running "$SERVICE_NAME"; then
            echo "Stopping [$SERVICE_NAME]..."
            systemctl stop "$SERVICE_NAME"
        fi

        ARTIFACT="$(get_artifact_name "$SERVICE_NAME")"
        copy_service_artifacts "$ARTIFACT" || exit 1

        if is_daemon_installed "$SERVICE_NAME"; then
            extract_launcher_script "$ARTIFACT" || exit 1

            echo "Starting [$SERVICE_NAME]..."
            systemctl start "$SERVICE_NAME" || exit $?
        elif is_cron_installed "$SERVICE_NAME"; then
            extract_cron_launcher_script "$ARTIFACT" || exit 1
        fi
    done
fi