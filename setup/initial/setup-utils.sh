#!/bin/bash
function require_root_user() {
    if [ $EUID -ne 0 ]; then
        echo "This script must be run as root user"
        exit 1
    fi
}

function init_credentials() {
    {
        echo "RELEASES_REPO_URL=$RELEASES_REPO_URL"
        echo "SNAPSHOT_REPO_URL=$SNAPSHOT_REPO_URL"
        echo "REPOSITORY_UN=$REPOSITORY_UN"
        echo "REPOSITORY_PWD='$REPOSITORY_PWD'"
        echo "TOMCAT_PATH=$TOMCAT_PATH"
        echo "TOMCAT_SERVICE=$TOMCAT_SERVICE"
        echo "TOMCAT_UN=$TOMCAT_UN"
        echo "TOMCAT_GROUP=$TOMCAT_GROUP"
        # shellcheck disable=SC2153
        echo "SERVICES_PATH=$SERVICES_PATH"
    } > "$SCRIPTS_PATH/credentials.conf"
    chown "$SCRIPTS_OWNER" "$SCRIPTS_PATH/credentials.conf"
    chmod 600 "$SCRIPTS_PATH/credentials.conf"
}

function generate_service_name() {
    local WEBSITE ARTIFACT SERVICE_NAME

    WEBSITE=$1
    ARTIFACT=$2

    if [ -n "$WEBSITE" ]; then
        SERVICE_NAME="${WEBSITE}_${ARTIFACT}"
    else
        SERVICE_NAME="${ARTIFACT}"
    fi

    echo "$SERVICE_NAME"
}

# Will export next variables: SERVICE_NAME, SERVICE_PATH, SERVICE_UN, SERVICE_GROUP
function config_service_env() {
    local WEBSITE ARTIFACT

    WEBSITE=$1
    ARTIFACT=$2

    export SERVICE_NAME
    SERVICE_NAME="$(generate_service_name "$WEBSITE" "$ARTIFACT")"

    # shellcheck disable=SC2153
    export SERVICE_PATH="$SERVICES_PATH/$SERVICE_NAME"
    export SERVICE_UN="$ARTIFACT"
    export SERVICE_GROUP="$ARTIFACT"
}

# Will export next variables: EC2_ID, EC2_REGION, EC2_URL_INTERNAL, EC2_IPV4
function config_ec2_env() {
    export EC2_ID
    export EC2_REGION
    export EC2_URL_INTERNAL
    export EC2_IPV4

    EC2_ID="$(ec2-metadata --instance-id | cut -d' ' -f2)"
    EC2_REGION=$(ec2-metadata --availability-zone | cut -d ' ' -f2 | sed 's/[a-z]$//')
    EC2_URL_INTERNAL=$(aws ec2 describe-tags --region "$EC2_REGION" --filters "Name=resource-id,Values=$EC2_ID" \
        "Name=resource-type,Values=instance" "Name=key,Values=Name" | jq ".Tags[0].Value" | sed -r 's/\"//g')
    EC2_IPV4="$(ec2-metadata --local-ipv4 | cut -d ' ' -f2)"
}

# Uses EC2_URL_INTERNAL, EC2_IPV4 variable
function init_ec2_instance() {
    if [ -z "$AWS_DOMAIN" ]; then
        echo "Update hostname and route 53 is cancelled"
        return 0
    fi

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
