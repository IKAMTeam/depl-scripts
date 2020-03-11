#!/bin/bash

if [ "$#" -ne 3 ]; then
    echo "### This script will automatically set up the services needed to run on the web server ###"
    echo "Before run this script you need to install Java 11, Tomcat 8.5 and Git on server"
    echo " "
    echo "Usage: $(basename "$0") <website> <website version> <database user (owner schema)> <database host:port:sid>"
    echo " "
    echo "Example: $(basename "$0") test.onevizion.com 20.3.0 prod01 db01.template.ov.internal:1521:P1"
    exit 1
fi

# shellcheck source=utils.sh
. "$(dirname "$0")/utils.sh"

require_root_user

PARAMS_FILE="$SCRIPTS_DIR/.params"

# Source a file for extra parameters (MAIN_PASSWORD, USER_PASSWORD, RPT_PASSWORD, PKG_PASSWORD)
# Used mainly to store passwords for the setup
# shellcheck disable=SC1090
source "$PARAMS_FILE"

set -o errexit
set -o pipefail
set -o nounset

WEBSITE=$1
VERSION=$2
DB_USER=$3
DB_URL=$4

# Install Tomcat (includes Java 11 (Correto))
amazon-linux-extras install -y tomcat8.5

init_ec2_instance

# Run setup-app-server.sh
"$(dirname "$0")/setup_web_server.sh" "$WEBSITE" "$VERSION" "$DB_USER" "$DB_URL" "$MAIN_PASSWORD" "$USER_PASSWORD" \
    "$PKG_PASSWORD"

# Update internal DNS
"$SCRIPTS_DIR/update-route53.sh"

# Finished
echo "Web server setup is complete."
