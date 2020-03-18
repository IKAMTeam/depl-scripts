#!/bin/bash
export AWS_DOMAIN="ov.internal"

function require_root_user() {
    if [ $EUID -ne 0 ]; then
        echo "This script must be run as root user"
        exit 1
    fi
}

function config_ec2_env() {
    export EC2_ID
    export EC2_REGION
    export EC2_URL_INTERNAL
    export EC2_IPV4

    EC2_ID="$(ec2-metadata --instance-id | cut -d' ' -f2)"
    EC2_REGION=$(ec2-metadata --availability-zone | cut -d ' ' -f2 | sed 's/[a-z]$//')
    EC2_URL_INTERNAL=$(aws ec2 describe-tags --region "$EC2_REGION" --filters "Name=resource-id,Values=$EC2_ID" \
        --filters "Name=key,Values=url-internal" | jq ".Tags[0].Value" | sed -r 's/\"//g')
    EC2_IPV4="$(ec2-metadata --local-ipv4 | cut -d ' ' -f2)"
}

function init_credentials() {
    {
        echo "RELEASES_REPO_URL=$RELEASES_REPO_URL"
        echo "SNAPSHOT_REPO_URL=$SNAPSHOT_REPO_URL"
        echo "REPOSITORY_UN=$REPOSITORY_UN"
        echo "REPOSITORY_PWD=$REPOSITORY_PWD"
    } > "$SCRIPTS_DIR/credentials.conf"
}

# Uses EC2_URL_INTERNAL, EC2_IPV4 variable
function init_ec2_instance() {
    # Install jq
    yum install -y jq

    config_ec2_env

    # Update hostname
    TARGET_DOMAIN="${EC2_URL_INTERNAL}.${AWS_DOMAIN}"
    hostnamectl set-hostname "$TARGET_DOMAIN"
    {
        echo -n "$EC2_IPV4 $TARGET_DOMAIN"
        echo " $EC2_URL_INTERNAL" | sed 's/\./-/g'
    } >> "/etc/hosts"

    echo "Updating Route 53..."
    update_route53
}

# Uses EC2_URL_INTERNAL, EC2_IPV4, AWS_DOMAIN variable
function update_route53() {
    local ZONE_ID
    ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "$AWS_DOMAIN" --max-items 1 | jq ".HostedZones[0].Id" | sed 's/^"\/hostedzone\///g' | sed 's/"//g')

    if [ -z "$ZONE_ID" ]; then
        echo "No Zone ID received for domain [$AWS_DOMAIN]!"
        return 1
    fi

    TARGET_DOMAIN="${EC2_URL_INTERNAL}.${AWS_DOMAIN}"

    echo "Zone ID: $ZONE_ID"
    echo "Target domain: $TARGET_DOMAIN"

    # Create a new A record on Route 53, replacing the old entry if nessesary
    aws route53 change-resource-record-sets --hosted-zone-id "$ZONE_ID" --change-batch file:///dev/stdin <<EOF
{
  "Comment": "Updating internal URL.",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${TARGET_DOMAIN}",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [
          {
            "Value": "${EC2_IPV4}"
          }
        ]
      }
    }
  ]
}
EOF
}
