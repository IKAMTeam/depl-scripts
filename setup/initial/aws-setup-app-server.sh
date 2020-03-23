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

# shellcheck source=aws-setup.conf.template
. "$CONFIG_FILE"

trap 'rm -f $CONFIG_FILE &>/dev/null' EXIT

set -o errexit
set -o pipefail

init_ec2_instance

# Install Java 11 (Correto)
amazon-linux-extras install -y java-openjdk11

yum install -y python3

# Sometimes these libraries are missing from default install
python3 -m pip install argparse
python3 -m pip install oauth
python3 -m pip install PrettyTable
python3 -m pip install pyserial
python3 -m pip install requests
python3 -m pip install onevizion
python3 -m pip install pysftp
python3 -m pip install datetime
python3 -m pip install pandas
python3 -m pip install boto3

# Run setup-app-server.sh
"$(dirname "$0")/setup-app-server.sh" "$CONFIG_FILE"
