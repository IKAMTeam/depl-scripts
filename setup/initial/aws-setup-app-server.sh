#!/bin/bash

if [ "$#" -ne 4 ]; then
    echo "### This script will automatically set up the services needed to run on the app server (based on AWS) ###"
    echo "Usage: $(basename "$0") <website> <website version> <database user (owner schema)> <database host:port:sid>"
    echo " "
    echo "Example: $(basename "$0") test.onevizion.com 20.3.0 prod01 db01.template.ov.internal:1521:P1"
    exit 1
fi

# shellcheck source=utils.sh
. "$(dirname "$0")/utils.sh"

# shellcheck source=aws-utils.sh
. "$(dirname "$0")/aws-utils.sh"

require_root_user

set -o errexit
set -o pipefail
set -o nounset

WEBSITE=$1
VERSION=$2
DB_USER=$3
DB_URL=$4

# Install Java 11 (Correto)
amazon-linux-extras install -y java-openjdk11

init_ec2_instance

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
"$(dirname "$0")/setup_app_server.sh" "$WEBSITE" "$VERSION" "$DB_USER" "$DB_URL" "$MAIN_PASSWORD" "$USER_PASSWORD" \
    "$RPT_PASSWORD"

# Update internal DNS
"$SCRIPTS_DIR/update-route53.sh"
