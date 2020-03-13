#!/bin/bash

function init_ec2_instance() {
    # Install Git, jq
    yum install -y git jq

    EC2_ID="$(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
    URL_INTERNAL=$(aws ec2 describe-tags --region "us-east-1" --filters "Name=resource-id,Values=$EC2_ID" "Name=key,Values=url-internal" |
        jq ".Tags[0].Value" | sed -r 's/\"//g')
    ENV="${URL_INTERNAL#*.}"
    IPV4="$(ec2-metadata -o | cut -d ' ' -f2)"

    # Update hostname
    echo "HOSTNAME=$URL_INTERNAL" >>"/etc/sysconfig/network"
    echo -n "$IPV4 ${URL_INTERNAL}.ov.internal" >>"/etc/hosts"
    echo " $URL_INTERNAL" | sed 's/\./-/g' >>"/etc/hosts"

    # Update nickname for terms
    echo "export NICKNAME=$URL_INTERNAL" | sed 's/\./-/g' >"/etc/profile.d/prompt.sh"
}
