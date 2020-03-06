#!/bin/bash
export SERVICES_PATH="/opt"

export TOMCAT_SERVICE="tomcat"
export TOMCAT_UN="tomcat"
export TOMCAT_GROUP="tomcat"
export TOMCAT_WAIT_LOG="catalina.log"

export APP_LAUNCHER_TEMPLATE_NAME="app-launcher.template"
export APP_LAUNCHER_IN_ARTIFACT_NAME="templates/app-launcher.sh"

export CRON_LAUNCHER_TEMPLATE_NAME="cron-launcher.template"
export CRON_LAUNCHER_IN_ARTIFACT_NAME="templates/cron-launcher.sh"

export ENV_CONF_TEMPLATE_NAME="environment.template"
export ENV_CONF_IN_ARTIFACT_NAME="templates/environment.conf"

export SYSTEMD_CONF_TEMPLATE_NAME="service.template"
export SYSTEMD_CONF_IN_ARTIFACT_NAME="templates/systemd.service"

export CLEANUP_TMP_FILES=""

# shellcheck source=credentials.conf
. "$(dirname "$0")/credentials.conf"

function require_root_user() {
    if [ $EUID -ne 0 ]; then
        echo "This script must be run as root user"
        exit 1
    fi
}

function get_depl_env() {
    local VERSION DEPL_ENV
    VERSION=$1

    case $VERSION in
    *-SNAPSHOT)
        DEPL_ENV="dev"
        ;;
    *-RC?)
        DEPL_ENV="uat"
        ;;
    *)
        DEPL_ENV="prod"
        ;;
    esac

    echo $DEPL_ENV
}

function download_artifact() {
    local ARTIFACT VERSION DOWNLOAD_PATH DEPL_ENV DOWNLOAD_SUFFIX

    ARTIFACT=$1
    VERSION=$2
    DOWNLOAD_PATH=$3
    DEPL_ENV="$(get_depl_env "$VERSION")"

    if [ "$ARTIFACT" == "ps-web" ]; then
        DOWNLOAD_SUFFIX=".war"
    else
        DOWNLOAD_SUFFIX="-shaded.jar"
    fi

    case $DEPL_ENV in
    dev)
        DEV_METADATA_LINK="$SNAPSHOT_REPO_URL/com/onevizion/$ARTIFACT/$VERSION/maven-metadata.xml"
        DEV_METADATA_DL_PATH="$(mktemp --suffix="_metadataxml")"

        if ! wget -q --no-check-certificate --output-document="$DEV_METADATA_DL_PATH" --http-user="$REPOSITORY_UN" --http-passwd="$REPOSITORY_PWD" "$DEV_METADATA_LINK"; then
            echo "Can't download metadata for full dev artifact version by link [$DEV_METADATA_LINK]. Wrong artifact or version"
            rm -f "$DEV_METADATA_DL_PATH"
            return 1
        else
            echo "Metadata downloaded successfully"
        fi

        TIMESTAMP=$(grep '<timestamp' "$DEV_METADATA_DL_PATH" | cut -f2 -d">" | cut -f1 -d"<")
        BUILD_NUMBER=$(grep '<buildNumber' "$DEV_METADATA_DL_PATH" | cut -f2 -d">" | cut -f1 -d"<")

        rm -f "$DEV_METADATA_DL_PATH"

        DEV_SNAPSHOT_VERSION="${VERSION//-SNAPSHOT/}"
        ARTIFACT_DL_URL="$SNAPSHOT_REPO_URL/com/onevizion/$ARTIFACT/$DEV_SNAPSHOT_VERSION-SNAPSHOT/$ARTIFACT-$DEV_SNAPSHOT_VERSION-$TIMESTAMP-$BUILD_NUMBER$DOWNLOAD_SUFFIX"
        ;;
    uat)
        ARTIFACT_DL_URL="$RELEASES_REPO_URL/com/onevizion/$ARTIFACT/$VERSION/$ARTIFACT-$VERSION$DOWNLOAD_SUFFIX"
        ;;
    prod)
        ARTIFACT_DL_URL="$RELEASES_REPO_URL/com/onevizion/$ARTIFACT/$VERSION/$ARTIFACT-$VERSION$DOWNLOAD_SUFFIX"
        ;;
    esac

    echo "Downloading [$ARTIFACT_DL_URL] into [$DOWNLOAD_PATH]..."

    if ! wget -q --no-check-certificate --output-document="$DOWNLOAD_PATH" --http-user="$REPOSITORY_UN" --http-passwd="$REPOSITORY_PWD" "$ARTIFACT_DL_URL"; then
        rm -f "$DOWNLOAD_PATH"
        echo "Can't download artifact by link [$ARTIFACT_DL_URL]"
        return 1
    else
        echo "[$ARTIFACT:$VERSION] downloaded successfully"
    fi
}

# Uses SERVICES_PATH variable
function check_service_exists_or_exit() {
    local SERVICE_NAME
    SERVICE_NAME=$1

    if [ ! -d "$SERVICES_PATH/$SERVICE_NAME" ]; then
        echo "No OneVizion service with name [$SERVICE_NAME] is available!"
        bash "$(dirname "$0")/list-services.sh"
        exit 1
    fi
}

function extract_artifact_version() {
    local ARTIFACT_JAR
    ARTIFACT_JAR=$1

    TMP_DIR="$(mktemp -d)"
    delete_on_exit "$TMP_DIR"

    if ! unzip -q -j "$ARTIFACT_JAR" "META-INF/MANIFEST.MF" -d "$TMP_DIR"; then
        echo "Unable to extract [$ARTIFACT_JAR!/META-INF/MANIFEST.MF] to [$TMP_DIR]" 1>&2
        return 1
    fi

    grep 'Implementation-Version' "$TMP_DIR/MANIFEST.MF" | cut -d ' ' -f2
}

# Uses SERVICE_PATH, SERVICE_UN, SERVICE_GROUP, APP_LAUNCHER_IN_ARTIFACT_NAME, APP_LAUNCHER_TEMPLATE_NAME variables
function extract_launcher_script() {
    local ARTIFACT OUTPUT_FILE
    ARTIFACT="$1"
    # shellcheck disable=SC2153
    OUTPUT_FILE="$SERVICE_PATH/app-launcher.sh"

    echo "Extracting launcher script..."

    # shellcheck disable=SC2153
    extract_jar_file "$ARTIFACT" "$APP_LAUNCHER_IN_ARTIFACT_NAME" "$OUTPUT_FILE" || {
        echo "Fallback to default app-launcher..."
        cp "$(dirname "$0")/$APP_LAUNCHER_TEMPLATE_NAME" "$OUTPUT_FILE" || return 1
    }

    chown "$SERVICE_UN:$SERVICE_GROUP" "$OUTPUT_FILE" || return 1
    chmod u+x,g+x "$OUTPUT_FILE" || return 1
}

# Uses SERVICE_PATH, SERVICE_UN, SERVICE_GROUP, CRON_LAUNCHER_IN_ARTIFACT_NAME, CRON_LAUNCHER_TEMPLATE_NAME variables
# Will export CRON_LAUNCHER_SCRIPT_PATH variable
function extract_cron_launcher_script() {
    local ARTIFACT OUTPUT_FILE
    ARTIFACT="$1"

    # shellcheck disable=SC2153
    OUTPUT_FILE="$SERVICE_PATH/cron-launcher.sh"

    echo "Extracting cron launcher script..."

    # shellcheck disable=SC2153
    extract_jar_file "$ARTIFACT" "$CRON_LAUNCHER_IN_ARTIFACT_NAME" "$OUTPUT_FILE" || {
        echo "Fallback to default cron-launcher..."
        cp "$(dirname "$0")/$CRON_LAUNCHER_TEMPLATE_NAME" "$OUTPUT_FILE" || return 1
    }

    chown "$SERVICE_UN:$SERVICE_GROUP" "$OUTPUT_FILE" || return 1
    chmod u+x,g+x "$OUTPUT_FILE" || return 1

    export CRON_LAUNCHER_SCRIPT_PATH="$OUTPUT_FILE"
}

# Uses ENV_CONF_IN_ARTIFACT_NAME, ENV_CONF_TEMPLATE_NAME variables
function extract_environment_conf() {
    local ARTIFACT OUTPUT_FILE
    ARTIFACT="$1"
    OUTPUT_FILE="$2"

    echo "Extracting environment configuration template..."

    # shellcheck disable=SC2153
    extract_jar_file "$ARTIFACT" "$ENV_CONF_IN_ARTIFACT_NAME" "$OUTPUT_FILE" || {
        echo "Fallback to default environment configuration template..."
        cp "$(dirname "$0")/$ENV_CONF_TEMPLATE_NAME" "$OUTPUT_FILE" || return 1
    }

    chown "$SERVICE_UN:$SERVICE_GROUP" "$OUTPUT_FILE" || return 1
}

# Uses SYSTEMD_CONF_IN_ARTIFACT_NAME, SYSTEMD_CONF_TEMPLATE_NAME variables
function extract_systemd_service() {
    local ARTIFACT OUTPUT_FILE
    ARTIFACT="$1"
    OUTPUT_FILE="$2"

    echo "Extracting systemd service template..."

    # shellcheck disable=SC2153
    extract_jar_file "$ARTIFACT" "$SYSTEMD_CONF_IN_ARTIFACT_NAME" "$OUTPUT_FILE" || {
        echo "Fallback to default systemd service template..."
        cp "$(dirname "$0")/$SYSTEMD_CONF_TEMPLATE_NAME" "$OUTPUT_FILE" || return 1
    }
}

# Uses SERVICE_PATH variable
function extract_jar_file() {
    local ARTIFACT INPUT_FILE OUTPUT_FILE SERVICE_JAR
    ARTIFACT="$1"
    INPUT_FILE="$2"
    OUTPUT_FILE="$3"

    # shellcheck disable=SC2153
    SERVICE_JAR="$SERVICE_PATH/$ARTIFACT.jar"

    TMP_DIR="$(mktemp -d)"

    rm -f "$OUTPUT_FILE"

    if unzip -q -j "$SERVICE_JAR" "$INPUT_FILE" -d "$TMP_DIR"; then
        cp "$TMP_DIR/$INPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || return 1
    else
        echo "Unable to extract [$SERVICE_JAR!/$INPUT_FILE] to [$TMP_DIR]"
        rm -rf "$TMP_DIR"

        return 1
    fi

    rm -rf "$TMP_DIR"
}

# Uses SERVICE_PATH, SERVICE_UN, SERVICE_GROUP variables
function copy_service_jar() {
    local ARTIFACT DOWNLOAD_PATH SERVICE_JAR

    ARTIFACT="$1"
    DOWNLOAD_PATH="$2"
    # shellcheck disable=SC2153
    SERVICE_JAR="$SERVICE_PATH/$ARTIFACT.jar"

    echo "Copying [$DOWNLOAD_PATH]($ARTIFACT) to [$SERVICE_JAR]..."

    rm -f "$SERVICE_JAR"
    cp "$DOWNLOAD_PATH" "$SERVICE_JAR" || return 1
    chmod 660 "$SERVICE_JAR" || return 1
    chown "$SERVICE_UN:$SERVICE_GROUP" "$SERVICE_JAR" || return 1
}

function is_daemon_installed() {
    local SERVICE_NAME
    SERVICE_NAME=$1

    if systemctl is-enabled "$SERVICE_NAME" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

function is_daemon_running() {
    local SERVICE_NAME
    SERVICE_NAME=$1

    if systemctl is-active "$SERVICE_NAME" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

function is_cron_installed() {
    local SERVICE_NAME SERVICE_UN SERVICE_PATH CRON_LAUNCHER_SCRIPT_PATH
    SERVICE_NAME=$1

    SERVICE_UN="$(get_artifact_name "$SERVICE_NAME")"
    SERVICE_PATH="$SERVICES_PATH/$SERVICE_NAME"
    CRON_LAUNCHER_SCRIPT_PATH="$SERVICE_PATH/cron-launcher.sh"

    if crontab -u "$SERVICE_UN" -l 2>/dev/null | grep "$CRON_LAUNCHER_SCRIPT_PATH" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

function get_artifact_name() {
    local SERVICE_NAME
    SERVICE_NAME=$1

    cut -d '_' -f2 <<<"$SERVICE_NAME"
}

function get_website_name() {
    local SERVICE_NAME
    SERVICE_NAME=$1

    cut -d '_' -f1 <<<"$SERVICE_NAME"
}

function generate_service_name() {
    local WEBSITE ARTIFACT SUFFIX SERVICE_NAME

    WEBSITE=$1
    ARTIFACT=$2
    SUFFIX=$3

    SERVICE_NAME="${WEBSITE}_${ARTIFACT}"
    if [ -n "$SUFFIX" ]; then
        SERVICE_NAME="${SERVICE_NAME}_${SUFFIX}"
    fi

    echo "$SERVICE_NAME"
}

# Will export next variables: SERVICE_NAME, SERVICE_PATH, SERVICE_UN, SERVICE_GROUP, JAR_NAME, JAR_PATH
function config_service() {
    local WEBSITE ARTIFACT SUFFIX

    WEBSITE=$1
    ARTIFACT=$2
    SUFFIX=$3

    # shellcheck disable=SC2153
    if [ ! -d "$SERVICES_PATH" ]; then
        echo "Creating services directory [$SERVICES_PATH]..."
        mkdir -p "$SERVICES_PATH" || return 1
    fi

    export SERVICE_NAME
    SERVICE_NAME="$(generate_service_name "$WEBSITE" "$ARTIFACT" "$SUFFIX")"

    # shellcheck disable=SC2153
    export SERVICE_PATH="$SERVICES_PATH/$SERVICE_NAME"
    export SERVICE_UN="$ARTIFACT"
    export SERVICE_GROUP="$ARTIFACT"

    echo "Service [$SERVICE_NAME] will be created under [$SERVICE_PATH] directory and [$SERVICE_UN:$SERVICE_GROUP] account"

    # Check group existence
    if getent group "$SERVICE_GROUP" >/dev/null; then
        echo "[$SERVICE_GROUP] group is already exists"
    else
        groupadd -r "$SERVICE_GROUP"
        echo "[$SERVICE_GROUP] group added"
    fi

    # Check user existence
    if getent passwd "$SERVICE_UN" >/dev/null; then
        echo "[$SERVICE_UN] user is already exists"
    else
        useradd -c "$SERVICE_UN" -g "$SERVICE_GROUP" -s /sbin/nologin -r -d "$SERVICES_PATH" "$SERVICE_UN"
        echo "[$SERVICE_UN] user added"
    fi

    mkdir "$SERVICE_PATH" || return 1
    mkdir "$SERVICE_PATH/logs" || return 1
    chown -R "$SERVICE_UN:$SERVICE_GROUP" "$SERVICE_PATH" || return 1
    (find "$SERVICE_PATH" -type d -print0 | xargs -0 chmod g+s) || return 1
    setfacl -d -m u::rwx "$SERVICE_PATH" || return 1
    setfacl -d -m g::rwx "$SERVICE_PATH" || return 1
    setfacl -d -m o::--- "$SERVICE_PATH" || return 1

    export JAR_NAME
    JAR_NAME="$ARTIFACT"

    # shellcheck disable=SC2034
    export JAR_PATH="$SERVICE_PATH/${JAR_NAME}.jar"
}

# Will export next variables: REPORT_EXEC_DOWNLOAD_PATH, EXPORT_EXEC_DOWNLOAD_PATH, DOWNLOAD_PATH
function download_service_artifacts() {
    local ARTIFACT VERSION
    ARTIFACT="$1"
    VERSION="$2"

    if [ "$ARTIFACT" == "report-scheduler" ] || [ "$ARTIFACT" == "services" ]; then
        REPORT_EXEC_DOWNLOAD_PATH="$(mktemp --suffix="_report-exec")"
        delete_on_exit "$REPORT_EXEC_DOWNLOAD_PATH"
        download_artifact "report-exec" "$VERSION" "$REPORT_EXEC_DOWNLOAD_PATH" || return 1

        EXPORT_EXEC_DOWNLOAD_PATH="$(mktemp --suffix="_export-exec")"
        delete_on_exit "$EXPORT_EXEC_DOWNLOAD_PATH"
        download_artifact "export-exec" "$VERSION" "$EXPORT_EXEC_DOWNLOAD_PATH" || return 1
    fi

    DOWNLOAD_PATH="$(mktemp --suffix="_$ARTIFACT")"
    delete_on_exit "$DOWNLOAD_PATH"
    download_artifact "$ARTIFACT" "$VERSION" "$DOWNLOAD_PATH" || return 1
}

function copy_service_artifacts() {
    local ARTIFACT
    ARTIFACT="$1"

    copy_service_jar "$ARTIFACT" "$DOWNLOAD_PATH" || return 1

    if [ "$ARTIFACT" == "report-scheduler" ] || [ "$ARTIFACT" == "services" ]; then
        copy_service_jar "report-exec" "$REPORT_EXEC_DOWNLOAD_PATH" || return 1
        copy_service_jar "export-exec" "$EXPORT_EXEC_DOWNLOAD_PATH" || return 1
    fi
}

function wait_log() {
    local LOG_FILE_PATH SUCCESS_STRING FAILED_STRING TIMEOUT FIFO_PATH OUT_PATH

    LOG_FILE_PATH=$1
    SUCCESS_STRING=$2
    FAILED_STRING=$3
    TIMEOUT=$4

    FIFO_PATH="$(mktemp --dry-run --suffix="_fifo")"
    OUT_PATH="$(mktemp --suffix="_out")"
    mkfifo "$FIFO_PATH" || return 1

    delete_on_exit "$FIFO_PATH"
    delete_on_exit "$OUT_PATH"

    set +m
    {
        if ! timeout "$TIMEOUT" grep -m 1 -e "$SUCCESS_STRING" -e "$FAILED_STRING" "$FIFO_PATH"; then
            echo "Waiting time is exceeded."
        fi
    } >"$OUT_PATH" &

    # shellcheck disable=SC2024
    tail -F -n 0 "$LOG_FILE_PATH" --pid $! 2>/dev/null >>"$FIFO_PATH"

    # Show grep output
    cat "$OUT_PATH"

    # Match string again for generate return code
    if grep -m 1 -e "$SUCCESS_STRING" "$OUT_PATH" &>/dev/null; then
        return 0
    else
        echo "(log file: $LOG_FILE_PATH)"
        return 1
    fi
}

# Uses TOMCAT_UN, TOMCAT_GROUP variables
function unpack_ps_war() {
    local WEBAPP_PATH DOWNLOAD_PATH

    WEBAPP_PATH=$1
    DOWNLOAD_PATH=$2

    if test -d "$WEBAPP_PATH"; then
        rm -rf "$WEBAPP_PATH" || return 1
    fi

    mkdir -p "$WEBAPP_PATH"
    unzip -q "$DOWNLOAD_PATH" -d "$WEBAPP_PATH" || return 1

    # Set permissions
    chown -R "$(whoami):$TOMCAT_GROUP" "$WEBAPP_PATH" || return 1
    (find "$WEBAPP_PATH" -type d -print0 | xargs -0 chmod g-w,g+x,o-r,o-w,o-x) || return 1
    (find "$WEBAPP_PATH" -type f -print0 | xargs -0 chmod g-w,o-r,o-w,o-x) || return 1
    (find "$WEBAPP_PATH" -maxdepth 1 -type d \( -name 'css' -or -name 'img' \) -print0 | xargs -0 chmod -R g+w) || exit 1
}

function cleanup_tomcat() {
    local TOMCAT_PATH

    TOMCAT_PATH=$1

    rm -rf "$TOMCAT_PATH"/work/*
    rm -rf "$TOMCAT_PATH"/logs/ps/*
    rm -rf "$TOMCAT_PATH"/logs/catalina.log "$TOMCAT_PATH"/logs/catalina.out
}

# Uses CLEANUP_TMP_FILES variable
function delete_on_exit() {
    export CLEANUP_TMP_FILES="$CLEANUP_TMP_FILES $1"
}

# Uses CLEANUP_TMP_FILES variable
function cleanup_tmp() {
    if [ -n "$CLEANUP_TMP_FILES" ]; then
        # shellcheck disable=SC2086
        rm -rf $CLEANUP_TMP_FILES &> /dev/null
    fi
}

trap cleanup_tmp EXIT ERR
