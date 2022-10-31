#!/bin/bash

function usage() {
    echo "### Script to install new service to run on schedule ###"
    echo "Usage: $(basename "$0") <website> <artifact> [--suffix <suffix>] <version> [--aes-password <aes password>] <schedule> <jar launch args>"
    echo " "
    echo "Usage for syncs3: $(basename "$0") <website> <artifact> [--suffix <suffix>] <version> [--aes-password <aes_password>] <schedule> <owner_schema_username>/<owner_schema_password>@<owner_schema_connect_identifier> [for_last_N_days]"
    echo "Usage for monitoring-refresh-config: $(basename "$0") monitoring-refresh-config <schedule>"
    echo " "
    echo "Where *_schema_connect_identifier is Oracle host:port:sid or host:port/service_name"
    echo "Where schedule is Cron format like ""0 3 * * *"" for run every day at 3:00 AM"
}

function schedule_cron_job() {
    local ARTIFACT SCHEDULE
    ARTIFACT=$1
    SCHEDULE=$2

    echo "Scheduling cron job for [$SERVICE_NAME] for run at [$SCHEDULE]..."

    if is_python_service "$ARTIFACT"; then
        copy_python_cron_launcher_script "$ARTIFACT" || return 1
    else
        extract_cron_launcher_script "$ARTIFACT" || return 1
    fi

    echo "Dropping record from crontab if exists..."
    crontab -u "$SERVICE_UN" -l | grep -v "$CRON_LAUNCHER_SCRIPT_PATH" | crontab -u "$SERVICE_UN" - || return 1

    echo "Adding record to crontab..."
    (
        crontab -u "$SERVICE_UN" -l
        echo "$SCHEDULE ""$CRON_LAUNCHER_SCRIPT_PATH"""
    ) | crontab -u "$SERVICE_UN" - || return 1
}

function install_java_service() {
    if [ "$#" -lt 4 ]; then
        usage
        return 1
    fi

    local WEBSITE ARTIFACT SUFFIX VERSION AES_PASSWORD SCHEDULE

    WEBSITE=$1
    ARTIFACT=$2

    shift
    shift

    if [ "$1" == "--suffix" ]; then
        SUFFIX=$2
        shift
        shift
    fi

    VERSION=$1
    shift

    if [ "$1" == "--aes-password" ]; then
        AES_PASSWORD=$2
        shift
        shift
    fi

    SCHEDULE=$1
    shift

    if [ "$#" -eq 0 ]; then
        usage
        return 1
    fi

    # shellcheck disable=SC2034
    export JAR_OPTS=$*

    require_root_user
    config_service "$WEBSITE" "$ARTIFACT" "$SUFFIX" || return 1
    download_service_artifacts "$ARTIFACT" "$VERSION" || return 1

    copy_service_artifacts "$ARTIFACT" || return 1

    # Set AES password if specified
    if [ -n "$AES_PASSWORD" ]; then
        echo "aesPassword=$AES_PASSWORD" > "$SERVICE_PATH/ov.properties"
    fi

    # Replace $ -> \$ to prevent bash eat it on launch stage
    export JAR_OPTS=${JAR_OPTS//$/\\$}

    prepare_java_environment_conf "$ARTIFACT" || return 1
    schedule_cron_job "$ARTIFACT" "$SCHEDULE" || return 1
}

function install_python_and_dependencies() {
    local ARTIFACT
    ARTIFACT=$1

    echo "Installing Python..."
    yum install -y python3 || return 1

    PYTHON_REQUIREMENTS_FILE="$(get_python_service_requirements_file "$ARTIFACT")"
    if [ -f "$PYTHON_REQUIREMENTS_FILE" ]; then
        echo "Installing Python dependencies (to service user)..."
        sudo -u "$SERVICE_UN" python3 -m pip install -r "$PYTHON_REQUIREMENTS_FILE" --upgrade --user || return 1
    fi
}

function install_python_service() {
    if [ "$#" -lt 2 ]; then
        usage
        return 1
    fi

    local ARTIFACT SCHEDULE
    ARTIFACT=$1
    SCHEDULE=$2

    require_root_user
    config_service "" "$ARTIFACT" || return 1

    copy_service_artifacts "$ARTIFACT" || return 1
    install_python_and_dependencies "$ARTIFACT" || return 1
    prepare_python_environment_conf "$ARTIFACT" || return 1
    schedule_cron_job "$ARTIFACT" "$SCHEDULE" || return 1
}

# shellcheck source=utils.sh
. "$(dirname "$0")/utils.sh"

if [ "$#" -eq 0 ]; then
    usage
    exit 1
fi

if is_python_service "$1"; then
    install_python_service "$@" || exit 1
else
    install_java_service "$@" || exit 1
fi
