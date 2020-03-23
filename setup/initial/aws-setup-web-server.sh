#!/bin/bash

function usage() {
    echo "### This script will automatically set up the services needed to run on the web server (based on AWS) ###"
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

# shellcheck source=aws-setup.conf.template
. "$CONFIG_FILE"

trap 'rm -f $CONFIG_FILE &>/dev/null' EXIT

set -o errexit
set -o pipefail

init_ec2_instance

# Install Tomcat (includes Java 11 (Correto))
amazon-linux-extras install -y tomcat8.5

# Run setup-web-server.sh
"$(dirname "$0")/setup-web-server.sh" "$CONFIG_FILE"
