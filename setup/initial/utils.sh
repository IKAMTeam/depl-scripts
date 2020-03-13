#!/bin/bash

function require_root_user() {
    if [ $EUID -ne 0 ]; then
        echo "This script must be run as root user"
        exit 1
    fi
}

# Uses AWS_REGION variable
function init_ec2_instance() {
    # Install Git, jq
    yum install -y git jq

    EC2_ID="$(ec2-metadata --instance-id | cut -d' ' -f2)"
    URL_INTERNAL=$(aws ec2 describe-tags --region "$AWS_REGION" --filters "Name=resource-id,Values=$EC2_ID" \
        --filters "Name=key,Values=url-internal" | jq ".Tags[0].Value" | sed -r 's/\"//g')
    ENV="${URL_INTERNAL#*.}"
    IPV4="$(ec2-metadata --local-ipv4 | cut -d ' ' -f2)"

    # Update hostname
    echo "HOSTNAME=$URL_INTERNAL" >>"/etc/sysconfig/network"
    echo -n "$IPV4 ${URL_INTERNAL}.ov.internal" >>"/etc/hosts"
    echo " $URL_INTERNAL" | sed 's/\./-/g' >>"/etc/hosts"

    # Update nickname for terms
    echo "export NICKNAME=$URL_INTERNAL" | sed 's/\./-/g' >"/etc/profile.d/prompt.sh"
}
