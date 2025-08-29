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

set -o allexport
eval "$CONFIG_DATA"
set +o allexport

set -o errexit
set -o pipefail

init_ec2_instance

# Install Java 21 (Correto)
install_java_21

# Sometimes these libraries are missing from default install
retry yum install -y python3-pip

# python3-devel, Development Tools packages are needed to build wheels including C/C++ code
retry yum install -y python3-devel
retry yum group install -y "Development Tools"

python3 -m pip install wheel || true

# Run setup-app-server.sh
"$(dirname "$0")/setup-app-server.sh" "-" <<< "$CONFIG_DATA"
