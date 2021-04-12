#!/bin/bash

function usage() {
    echo "### This script will automatically set up the services needed to run on the app server (based on AWS) ###"
    echo " "
    echo "Usage: $(basename "$0") <config file>"
    echo " "
    echo "Example: $(basename "$0") aws-setup.conf"
}

if [ "$#" -ne 1 ]; then
    usage
    exit 1
fi

# shellcheck source=setup-utils.sh
. "$(dirname "$0")/setup-utils.sh"

require_root_user

CONFIG_FILE="$1"
CONFIG_DATA="$(cat "$CONFIG_FILE")"

eval "$CONFIG_DATA"

set -o errexit
set -o pipefail

init_ec2_instance

# Install Java 11 (Correto)
amazon-linux-extras install -y java-openjdk11

yum install -y python3

# Sometimes these libraries are missing from default install
function install_python_dependency() {
    python3 -m pip install "$1" || true
}

install_python_dependency argparse
install_python_dependency oauth
install_python_dependency PrettyTable
install_python_dependency pyserial
install_python_dependency requests
install_python_dependency onevizion
install_python_dependency pysftp
install_python_dependency datetime
install_python_dependency pandas
install_python_dependency boto3

# Run setup-app-server.sh
"$(dirname "$0")/setup-app-server.sh" "-" <<< "$CONFIG_DATA"
