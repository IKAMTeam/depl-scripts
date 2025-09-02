#!/bin/bash
export TOMCAT_WAIT_LOG="catalina.log"

export APP_LAUNCHER_TEMPLATE_NAME="setup/templates/app-launcher.template"
export APP_LAUNCHER_IN_ARTIFACT_NAME="templates/app-launcher.sh"

export CRON_LAUNCHER_TEMPLATE_NAME="setup/templates/cron-launcher.template"
export CRON_LAUNCHER_PYTHON_TEMPLATE_NAME="setup/templates/cron-launcher-python.template"
export CRON_LAUNCHER_IN_ARTIFACT_NAME="templates/cron-launcher.sh"

export ENV_CONF_TEMPLATE_NAME="setup/templates/environment.template"
export ENV_CONF_IN_ARTIFACT_NAME="templates/environment.conf"

export SYSTEMD_CONF_TEMPLATE_NAME="setup/templates/service.template"
export SYSTEMD_CONF_IN_ARTIFACT_NAME="templates/systemd.service"

export SERVER_XML_HOST_TEMPLATE_NAME="setup/templates/tomcat-host.template"

export MONITOR_XML_TEMPLATE_NAME="setup/templates/monitor-db-schemas.template"
export MONITOR_REFRESH_CONFIG_ARTIFACT_NAME="monitoring-refresh-config"
export MONITOR_REFRESH_CONFIG_UN="$MONITOR_REFRESH_CONFIG_ARTIFACT_NAME"
export MONITOR_GROUP="monitoring"

export PYTHON_SERVICE_NAMES=("$MONITOR_REFRESH_CONFIG_ARTIFACT_NAME")

export CLEANUP_TMP_FILES=""

export CREDENTIALS_CONF
if [ -z "$CREDENTIALS_CONF" ]; then
    CREDENTIALS_CONF="$(dirname "$0")/credentials.conf"
fi

set -o allexport
# shellcheck source=credentials.conf
. "$CREDENTIALS_CONF"
set +o allexport

if [ -z "$MONITORING_REPO_URL" ]; then
    export MONITORING_REPO_URL
    MONITORING_REPO_URL="[MONITORING_REPO_URL not set in credentials.conf]"
fi

function require_root_user() {
    if [ $EUID -ne 0 ]; then
        echo "This script must be run as root user"
        exit 1
    fi
}

function retry() {
    local RETRIES COUNT
    RETRIES=2
    COUNT=0

    until "$@"; do
        EXIT=$?
        WAIT=$((2 ** COUNT))
        COUNT=$((COUNT + 1))

        if [ "$COUNT" -lt "$RETRIES" ]; then
            echo "Retry $COUNT/$RETRIES exited $EXIT, retrying in $WAIT seconds..."
            sleep $WAIT
        else
            echo "Retry $COUNT/$RETRIES exited $EXIT, no more retries left."
            return $EXIT
        fi
    done

    return 0
}

function download_artifact() {
    local GROUP_ID ARTIFACT_ID VERSION PACKAGING ARTIFACT_CLASSIFIER DOWNLOAD_PATH MVN_ARTIFACT MVN_CACHE_DIR RETRY_INTERVAL RETRIES ARTIFACT_HUMAN_READABLE

    GROUP_ID=$1
    ARTIFACT_ID=$2
    VERSION=$3
    PACKAGING=$4
    ARTIFACT_CLASSIFIER=$5
    DOWNLOAD_PATH=$6

    RETRY_INTERVAL=30s

    MVN_ARTIFACT="$GROUP_ID:$ARTIFACT_ID:$VERSION"

    ARTIFACT_HUMAN_READABLE="$MVN_ARTIFACT:$PACKAGING"
    if [ -n "$ARTIFACT_CLASSIFIER" ]; then
        ARTIFACT_HUMAN_READABLE="$ARTIFACT_HUMAN_READABLE:$ARTIFACT_CLASSIFIER"
    fi

    MVN_CACHE_DIR="$(mktemp -d)"
    MVN_LOG="$(mktemp --suffix="_mvn_log")"

    delete_on_exit "$MVN_CACHE_DIR"
    delete_on_exit "$MVN_LOG"

    RETRIES="1"
    while [ "$RETRIES" -ge 0 ]; do
        echo "Downloading [$ARTIFACT_HUMAN_READABLE] to [$DOWNLOAD_PATH]..."

        if ! "$(dirname "$0")/maven/bin/mvn" --batch-mode \
            -Dmaven.repo.local="$MVN_CACHE_DIR" \
            org.apache.maven.plugins:maven-dependency-plugin:3.1.2:get \
            -Dtransitive=false \
            -Dartifact="$MVN_ARTIFACT" \
            -Dpackaging="$PACKAGING" \
            -Dclassifier="$ARTIFACT_CLASSIFIER" &> "$MVN_LOG"; then

            echo "Can't download artifact [$ARTIFACT_HUMAN_READABLE]:"
            grep -F '[ERROR]' "$MVN_LOG" || (
                echo "====== Start of Maven full log ======"
                cat "$MVN_LOG"
                echo "====== End of Maven full log ======"
            )
        else
            local GROUP_ID_DIR_NAME ARTIFACT_PATH DOWNLOAD_SUFFIX

            grep -F 'Downloading from' "$MVN_LOG" | tail -n1

            if [ -n "$ARTIFACT_CLASSIFIER" ]; then
                DOWNLOAD_SUFFIX="-${ARTIFACT_CLASSIFIER}.${PACKAGING}"
            else
                DOWNLOAD_SUFFIX=".${PACKAGING}"
            fi

            GROUP_ID_DIR_NAME=$(echo "$GROUP_ID" | tr "." "/")
            ARTIFACT_PATH="$MVN_CACHE_DIR/$GROUP_ID_DIR_NAME/$ARTIFACT_ID/$VERSION/${ARTIFACT_ID}-${VERSION}${DOWNLOAD_SUFFIX}"

            if cp -f "$ARTIFACT_PATH" "$DOWNLOAD_PATH"; then
                echo "[$ARTIFACT_HUMAN_READABLE] downloaded successfully"
                return 0
            else
                echo "Unable to copy [$ARTIFACT_PATH] to [$DOWNLOAD_PATH]"
            fi
        fi

        if [ "$RETRIES" -gt 0 ]; then
            echo "Waiting for the next try ($RETRY_INTERVAL)"
            sleep "$RETRY_INTERVAL"
        fi

        (( RETRIES-- ))
    done

    return 1
}

# Uses SERVICES_PATH variable
function check_service_exists_or_exit() {
    local SERVICE_NAME
    SERVICE_NAME=$1

    # shellcheck disable=SC2153
    if [ ! -d "$SERVICES_PATH/$SERVICE_NAME" ]; then
        echo "No OneVizion service with name [$SERVICE_NAME] is available!"
        bash "$(dirname "$0")/list-services.sh"
        exit 1
    fi
}

function extract_and_read_artifact_version() {
    init_cleanup

    local ARTIFACT_JAR
    ARTIFACT_JAR="$1"

    TMP_DIR="$(mktemp -d)"
    delete_on_exit "$TMP_DIR"

    if ! unzip -q -j "$ARTIFACT_JAR" "META-INF/MANIFEST.MF" -d "$TMP_DIR"; then
        echo "Unable to extract [$ARTIFACT_JAR!/META-INF/MANIFEST.MF] to [$TMP_DIR]" 1>&2
        return 1
    fi

    read_artifact_version "$TMP_DIR/MANIFEST.MF"
}

function read_artifact_version() {
    local MANIFEST_PATH
    MANIFEST_PATH="$1"

    grep 'Implementation-Version' "$MANIFEST_PATH" | cut -d ' ' -f2 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

function is_snapshot_version() {
    local VERSION
    VERSION="$1"

    [[ "$VERSION" == *-SNAPSHOT ]]
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
    delete_on_exit "$TMP_DIR"

    if unzip -q -j "$SERVICE_JAR" "$INPUT_FILE" -d "$TMP_DIR"; then
        cp "$TMP_DIR/$(basename "$INPUT_FILE")" "$OUTPUT_FILE" 2>/dev/null || return 1
    else
        echo "Unable to extract [$SERVICE_JAR!/$INPUT_FILE] to [$TMP_DIR]"
        return 1
    fi
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

# Uses SERVICE_PATH, SERVICE_UN, SERVICE_GROUP variables
function copy_python_service_files() {
    local ARTIFACT SETUP_PATH
    ARTIFACT="$1"

    SETUP_PATH="$(get_python_service_setup_directory "$ARTIFACT")"

    echo "Copying files from [$SETUP_PATH] to [$SERVICE_PATH]..."
    cp -rf "$SETUP_PATH"/* "$SERVICE_PATH"
    chown -R "$SERVICE_UN:$SERVICE_GROUP" "$SERVICE_PATH" || return 1
}

# Uses SERVICE_PATH, SERVICE_UN, SERVICE_GROUP variables
# Will export CRON_LAUNCHER_SCRIPT_PATH variable
function copy_python_cron_launcher_script() {
    local ARTIFACT OUTPUT_FILE
    ARTIFACT="$1"

    # shellcheck disable=SC2153
    OUTPUT_FILE="$SERVICE_PATH/cron-launcher.sh"

    echo "Copying cron launcher script..."

    cp "$(dirname "$0")/$CRON_LAUNCHER_PYTHON_TEMPLATE_NAME" "$OUTPUT_FILE" || return 1

    chown "$SERVICE_UN:$SERVICE_GROUP" "$OUTPUT_FILE" || return 1
    chmod u+x,g+x "$OUTPUT_FILE" || return 1

    export CRON_LAUNCHER_SCRIPT_PATH="$OUTPUT_FILE"
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

# Uses PYTHON_SERVICE_NAMES variable
function is_python_service() {
    local ARTIFACT_NAME
    ARTIFACT_NAME="$1"

    # shellcheck disable=SC2076
    if [[ ! " ${PYTHON_SERVICE_NAMES[*]} " =~ " ${ARTIFACT_NAME} " ]]; then
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

function get_python_service_requirements_file() {
    echo "${SERVICE_PATH}/python-requirements.txt"
}

function get_python_service_setup_directory() {
    local ARTIFACT_NAME
    ARTIFACT_NAME="$1"

    echo "$(get_python_services_setup_directory)/$ARTIFACT_NAME"
}

function get_python_services_setup_directory() {
    echo "$(dirname "$0")/setup/templates/python-services"
}

function get_service_conf_file() {
    local ARTIFACT_NAME
    ARTIFACT_NAME="$1"

    echo "$SERVICE_PATH/$(get_service_conf_filename "$ARTIFACT_NAME")"
}

function get_service_conf_filename() {
    local ARTIFACT_NAME
    ARTIFACT_NAME="$1"

    if is_python_service "$ARTIFACT_NAME"; then
        echo "${SERVICE_NAME}.conf"
    else
        echo "${JAR_NAME}.conf"
    fi
}

function generate_service_name() {
    local WEBSITE ARTIFACT SUFFIX SERVICE_NAME

    WEBSITE=$1
    ARTIFACT=$2
    SUFFIX=$3

    if [ -n "$WEBSITE" ]; then
        SERVICE_NAME="${WEBSITE}_${ARTIFACT}"
    else
        SERVICE_NAME="${ARTIFACT}"
    fi

    if [ -n "$SUFFIX" ]; then
        SERVICE_NAME="${SERVICE_NAME}_${SUFFIX}"
    fi

    echo "$SERVICE_NAME"
}

# Will export next variables: SERVICE_NAME, SERVICE_PATH, SERVICE_UN, SERVICE_GROUP
function config_service_env() {
    local WEBSITE ARTIFACT SUFFIX

    WEBSITE=$1
    ARTIFACT=$2
    SUFFIX=$3

    export SERVICE_NAME
    SERVICE_NAME="$(generate_service_name "$WEBSITE" "$ARTIFACT" "$SUFFIX")"

    # shellcheck disable=SC2153
    export SERVICE_PATH="$SERVICES_PATH/$SERVICE_NAME"
    export SERVICE_UN="$ARTIFACT"
    export SERVICE_GROUP="$ARTIFACT"
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

    config_service_env "$WEBSITE" "$ARTIFACT" "$SUFFIX"

    echo "Service [$SERVICE_NAME] will be created under [$SERVICE_PATH] directory and [$SERVICE_UN:$SERVICE_GROUP] account"

    # Check group existence
    if getent group "$SERVICE_GROUP" >/dev/null; then
        echo "[$SERVICE_GROUP] group is already exists"
    else
        groupadd -r "$SERVICE_GROUP"
        echo "[$SERVICE_GROUP] group added"
    fi

    mkdir -p "$SERVICE_PATH" || return 1

    # Check user existence
    if getent passwd "$SERVICE_UN" >/dev/null; then
        echo "[$SERVICE_UN] user is already exists"
    else
        useradd -c "$SERVICE_UN" -g "$SERVICE_GROUP" -s /sbin/nologin -r -d "$SERVICE_PATH" "$SERVICE_UN"
        echo "[$SERVICE_UN] user added"
    fi

    if ! is_python_service "$ARTIFACT"; then
        mkdir -p "$SERVICE_PATH/logs" || return 1
    fi
    chown -R "$SERVICE_UN:$SERVICE_GROUP" "$SERVICE_PATH" || return 1
    find "$SERVICE_PATH" -type d -exec chmod g+s,g+w {} + || return 1
    find "$SERVICE_PATH" -type f -exec chmod g+w {} + || return 1
    setfacl -d -m u::rwx "$SERVICE_PATH" || return 1
    setfacl -d -m g::rwx "$SERVICE_PATH" || return 1
    setfacl -d -m o::--- "$SERVICE_PATH" || return 1

    export JAR_NAME
    JAR_NAME="$ARTIFACT"

    # shellcheck disable=SC2034
    export JAR_PATH="$SERVICE_PATH/${JAR_NAME}.jar"

    if [ "$ARTIFACT" == "$MONITOR_REFRESH_CONFIG_ARTIFACT_NAME" ]; then
        echo "Grant access to monitoring service"
        if ! getent group "$MONITOR_GROUP" >/dev/null; then
            groupadd -r "$MONITOR_GROUP" || return 1
            echo "[$MONITOR_GROUP] group added"
        fi
        usermod --append --groups "$MONITOR_GROUP" "$MONITOR_REFRESH_CONFIG_UN" || return 1
    fi
}

# Will export next variables: REPORT_EXEC_DOWNLOAD_PATH, EXPORT_EXEC_DOWNLOAD_PATH, DOWNLOAD_PATH
function download_service_artifacts() {
    local GROUP_ID ARTIFACT_ID VERSION
    GROUP_ID=com.onevizion
    ARTIFACT_ID="$1"
    VERSION="$2"
    PACKAGING=jar
    ARTIFACT_CLASSIFIER=shaded

    if [ "$ARTIFACT_ID" == "report-scheduler" ] || [ "$ARTIFACT_ID" == "services" ]; then
        REPORT_EXEC_DOWNLOAD_PATH="$(mktemp --suffix="_report-exec")"
        delete_on_exit "$REPORT_EXEC_DOWNLOAD_PATH"
        download_artifact "$GROUP_ID" "report-exec" "$VERSION" "$PACKAGING" "$ARTIFACT_CLASSIFIER" "$REPORT_EXEC_DOWNLOAD_PATH" || return 1

        EXPORT_EXEC_DOWNLOAD_PATH="$(mktemp --suffix="_export-exec")"
        delete_on_exit "$EXPORT_EXEC_DOWNLOAD_PATH"
        download_artifact "$GROUP_ID" "export-exec" "$VERSION" "$PACKAGING" "$ARTIFACT_CLASSIFIER" "$EXPORT_EXEC_DOWNLOAD_PATH" || return 1
    fi

    DOWNLOAD_PATH="$(mktemp --suffix="_$ARTIFACT_ID")"
    delete_on_exit "$DOWNLOAD_PATH"
    download_artifact "$GROUP_ID" "$ARTIFACT_ID" "$VERSION" "$PACKAGING" "$ARTIFACT_CLASSIFIER" "$DOWNLOAD_PATH" || return 1
}

function copy_service_artifacts() {
    local ARTIFACT
    ARTIFACT="$1"

    if is_python_service "$ARTIFACT"; then
        copy_python_service_files "$ARTIFACT" || return 1
    else
        copy_service_jar "$ARTIFACT" "$DOWNLOAD_PATH" || return 1

        if [ "$ARTIFACT" == "report-scheduler" ] || [ "$ARTIFACT" == "services" ]; then
            copy_service_jar "report-exec" "$REPORT_EXEC_DOWNLOAD_PATH" || return 1
            copy_service_jar "export-exec" "$EXPORT_EXEC_DOWNLOAD_PATH" || return 1
        fi
    fi
}

function prepare_java_environment_conf() {
    local ARTIFACT ENV_CONF_EXTRACT_PATH
    ARTIFACT=$1

    ENV_CONF_EXTRACT_PATH="$(mktemp --suffix="_env_$ARTIFACT")"
    delete_on_exit "$ENV_CONF_EXTRACT_PATH"
    extract_environment_conf "$ARTIFACT" "$ENV_CONF_EXTRACT_PATH" || return 1

    (< "$ENV_CONF_EXTRACT_PATH" envsubst | tee "$(get_service_conf_file "$ARTIFACT")") >/dev/null || return 1
}

function prepare_python_environment_conf() {
    local ARTIFACT ENV_CONF_FILE ENV_CONF_TEMPLATE_FILE
    ARTIFACT=$1

    ENV_CONF_FILE="$(get_service_conf_file "$ARTIFACT")"
    ENV_CONF_TEMPLATE_FILE="$(get_python_services_setup_directory)/$(get_service_conf_filename "$ARTIFACT").template"

    (< "$ENV_CONF_TEMPLATE_FILE" envsubst | tee "$ENV_CONF_FILE") >/dev/null || return 1
    chown "$SERVICE_UN:$SERVICE_GROUP" "$ENV_CONF_FILE" || return 1
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
function extract_war_contents() {
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
    find "$WEBAPP_PATH" -type d -exec chmod g-w,g+x,o-r,o-w,o-x {} + || return 1
    find "$WEBAPP_PATH" -type f -exec chmod g-w,o-r,o-w,o-x {} + || return 1
    find "$WEBAPP_PATH" -maxdepth 1 -type d \( -name 'css' -or -name 'img' \) -exec chmod -R g+w {} + || exit 1
}

# Uses TOMCAT_PATH variable
function recalculate_tomcat_metaspace_size() {
    local MEM_CONF_FILE SERVER_XML_FILE METASPACE_SIZE_MB METASPACE_MAX_SIZE_MB
    MEM_CONF_FILE="$TOMCAT_PATH/conf/conf.d/setmem.conf"
    SERVER_XML_FILE="$TOMCAT_PATH/conf/server.xml"

    if [ ! -f "$MEM_CONF_FILE" ]; then
        echo "Can't recalculate metaspace size! File [$MEM_CONF_FILE] does not exist"
        return 0
    fi

    METASPACE_SIZE_MB="384"
    METASPACE_MAX_SIZE_MB="512"

    WEBSITE_COUNT="$(read_xml_value "$SERVER_XML_FILE" "Service/Engine[@name=\"Catalina\"]/Host" "name" | wc -l)"
    (( WEBSITE_COUNT-= 2 ))

    if [ "$WEBSITE_COUNT" -gt 0 ]; then
        (( METASPACE_SIZE_MB+= (128 * WEBSITE_COUNT) ))
        (( METASPACE_MAX_SIZE_MB+= (128 * WEBSITE_COUNT) ))
    fi

    sed -i "/^METASPACE_SIZE_MB=.*$/ c METASPACE_SIZE_MB=\"$METASPACE_SIZE_MB\"" "$MEM_CONF_FILE" || return 1
    sed -i "/^METASPACE_MAX_SIZE_MB=.*$/ c METASPACE_MAX_SIZE_MB=\"$METASPACE_MAX_SIZE_MB\"" "$MEM_CONF_FILE" || return 1
}

function read_xml_value() {
    local IN_FILE XPATH ATTR_NAME

    IN_FILE=$1
    XPATH=$2
    ATTR_NAME=$3

    "$(dirname "$0")/setup/read-xml-value.py" "$IN_FILE" "$XPATH" "$ATTR_NAME" || return 1
}

function cleanup_tomcat() {
    local TOMCAT_PATH

    TOMCAT_PATH=$1

    rm -rf "$TOMCAT_PATH"/work/*
    rm -rf "$TOMCAT_PATH"/logs/ps/*
    rm -rf "$TOMCAT_PATH"/logs/catalina.log "$TOMCAT_PATH"/logs/catalina.out
}

function is_tomcat_support_jakarta() {
    TOMCAT_MAJOR_VERSION="$(java -cp "$TOMCAT_PATH/lib/catalina.jar" "org.apache.catalina.util.ServerInfo" | grep 'Apache Tomcat/' | cut -d'/' -f2 | cut -d'.' -f1)"
    [ "$TOMCAT_MAJOR_VERSION" -ge 10 ]
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

# Should be called from subshells separately
function init_cleanup() {
    trap cleanup_tmp EXIT ERR
}

init_cleanup
