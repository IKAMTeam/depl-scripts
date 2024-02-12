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
CONFIG_DATA="$(cat "$CONFIG_FILE")"

set -o allexport
eval "$CONFIG_DATA"
set +o allexport

set -o errexit
set -o pipefail

init_ec2_instance

# Install Java 17 (Correto)
install_java_17

# Install Tomcat (includes Java 11 (Correto))
# Correto 11 can't be removed because Tomcat package depends on it
yum install -y tomcat9

# Temporary workaround to support legacy AWS ELB Health Check configuration
yum install -y iptables-services
systemctl enable iptables

iptables -t nat -I PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080
service iptables save

# Install yum plugin
yum install -y python3-dnf-plugin-post-transaction-actions

# Create yum post-action to restore permissions after Tomcat package install/update
(< "$SCRIPTS_PATH/setup/templates/yum/post-actions/tomcat.action" envsubst | tee "/etc/dnf/plugins/post-transaction-actions.d/tomcat.action") >/dev/null

# Run setup-web-server.sh
"$(dirname "$0")/setup-web-server.sh" "-" <<< "$CONFIG_DATA"
