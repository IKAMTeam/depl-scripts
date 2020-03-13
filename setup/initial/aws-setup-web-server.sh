#!/bin/bash

function usage() {
    echo "### This script will automatically set up the services needed to run on the web server ###"
    echo "Before run this script you need to install Java 11, Tomcat 8.5 and Git on server"
    echo " "
    echo "Usage: $(basename "$0") <config file>"
    echo " "
    echo "Example: $(basename "$0") aws-setup.conf"
}

if [ "$#" -ne 1 ]; then
    usage
    exit 1
fi

# shellcheck source=utils.sh
. "$(dirname "$0")/utils.sh"

require_root_user

CONFIG_FILE="$1"

# shellcheck source=aws-setup.conf.template
. "$CONFIG_FILE"

set -o errexit
set -o pipefail
set -o nounset

# Install Tomcat (includes Java 11 (Correto))
amazon-linux-extras install -y tomcat8.5

init_ec2_instance

# Run setup-web-server.sh
"$(dirname "$0")/setup_web_server.sh" "$CONFIG_FILE"

# Finished
echo "Web server setup is complete."
