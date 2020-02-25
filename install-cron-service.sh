#!/bin/bash

function usage() {
    echo "### Script for install new service for periodically run ###"
    echo "Usage: $(basename "$0") <website> <artifact> [--suffix <suffix>] <version> <schedule> <jar launch args>"
    echo " "
    echo "Usage for syncs3: $(basename "$0") <website> <artifact> [--suffix <suffix>] <version> <schedule> <owner_schema_username>/<owner_schema_password>@<owner_schema_connect_identifier> [for_last_N_days]"
    echo " "
    echo "Where *_schema_connect_identifier is Oracle host:port:sid or host:port/service_name"
    echo "Where schedule is Cron format like ""0 3 * * *"" for run every day at 3:00 AM"
}

if [ "$#" -lt 4 ]; then
    usage
    exit 1
fi

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

SCHEDULE=$1
shift

if [ "$#" -eq 0 ]; then
    usage
    exit 1
fi

# shellcheck disable=SC2034
export JAR_OPTS=$*

# shellcheck source=utils.sh
. "$(dirname "$0")/utils.sh"

require_root_user
config_service "$WEBSITE" "$ARTIFACT" "$SUFFIX" || exit 1
download_service_artifacts "$ARTIFACT" "$VERSION" || exit 1

copy_service_artifacts "$ARTIFACT" || exit 1

echo "Scheduling cron job for [$SERVICE_NAME] for run at [$SCHEDULE]..."

extract_cron_launcher_script "$ARTIFACT" || exit 1

ENV_CONF_EXTRACT_PATH="$(mktemp --suffix="_env_$ARTIFACT")"
delete_on_exit "$ENV_CONF_EXTRACT_PATH"
extract_environment_conf "$ARTIFACT" "$ENV_CONF_EXTRACT_PATH" || exit 1

(sudo cat "$ENV_CONF_EXTRACT_PATH" | envsubst | sudo tee "$SERVICE_PATH/${JAR_NAME}.conf") >/dev/null || exit 1

echo "Dropping record from crontab if exists..."
sudo crontab -u "$SERVICE_UN" -l | grep -v "$CRON_LAUNCHER_SCRIPT_PATH" | sudo crontab -u "$SERVICE_UN" - || exit 1

echo "Adding record to crontab..."
(
    sudo crontab -u "$SERVICE_UN" -l
    echo "$SCHEDULE ""$CRON_LAUNCHER_SCRIPT_PATH"""
) | sudo crontab -u "$SERVICE_UN" - || exit 1
