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
        echo "MONITORING_REPO_URL='$MONITORING_REPO_URL'"
        echo "MONITORING_REPO_UN='$MONITORING_REPO_UN'"
        echo "MONITORING_REPO_PWD='$MONITORING_REPO_PWD'"
        echo "TOMCAT_PATH=$TOMCAT_PATH"
        echo "TOMCAT_SERVICE=$TOMCAT_SERVICE"
        echo "TOMCAT_UN=$TOMCAT_UN"
        echo "TOMCAT_GROUP=$TOMCAT_GROUP"
        # shellcheck disable=SC2153
        echo "SERVICES_PATH=$SERVICES_PATH"
        echo
        echo "MONITOR_AWS_SQS_ACCESS_KEY='$MONITOR_AWS_SQS_ACCESS_KEY'"
        echo "MONITOR_AWS_SQS_SECRET_KEY='$MONITOR_AWS_SQS_SECRET_KEY'"
        echo "MONITOR_AWS_SQS_QUEUE_URL='$MONITOR_AWS_SQS_QUEUE_URL'"
        echo
        echo "MONITOR_WARN_MAIL_HOST='$MONITOR_WARN_MAIL_HOST'"
        echo "MONITOR_WARN_MAIL_PORT='$MONITOR_WARN_MAIL_PORT'"
        echo "MONITOR_WARN_MAIL_USERNAME='$MONITOR_WARN_MAIL_USERNAME'"
        echo "MONITOR_WARN_MAIL_PASSWORD='$MONITOR_WARN_MAIL_PASSWORD'"
        echo "MONITOR_WARN_MAIL_FROM='$MONITOR_WARN_MAIL_FROM'"
        echo "MONITOR_WARN_MAIL_TO='$MONITOR_WARN_MAIL_TO'"
        echo
        echo "MONITOR_ERROR_MAIL_HOST='$MONITOR_ERROR_MAIL_HOST'"
        echo "MONITOR_ERROR_MAIL_PORT='$MONITOR_ERROR_MAIL_PORT'"
        echo "MONITOR_ERROR_MAIL_USERNAME='$MONITOR_ERROR_MAIL_USERNAME'"
        echo "MONITOR_ERROR_MAIL_PASSWORD='$MONITOR_ERROR_MAIL_PASSWORD'"
        echo "MONITOR_ERROR_MAIL_FROM='$MONITOR_ERROR_MAIL_FROM'"
        echo "MONITOR_ERROR_MAIL_TO='$MONITOR_ERROR_MAIL_TO'"
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

# Uses EC2_URL_INTERNAL, EC2_IPV4 variables
function init_ec2_instance() {
    install_cloudwatch_agent
    update_motd

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

    # Update bashrc
    sed -i "s/\\\h/\${HOSTNAME%.$AWS_DOMAIN}/g" /etc/bashrc

    echo "Updating Route 53..."
    update_route53
}

function install_cloudwatch_agent() {
    local CONF_FILE
    CONF_FILE="/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json"

    amazon-linux-extras install -y collectd
    yum install -y amazon-cloudwatch-agent

    tee "$CONF_FILE" <<'EOF'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "cwagent"
  },
  "metrics": {
    "append_dimensions": {
      "AutoScalingGroupName": "${aws:AutoScalingGroupName}",
      "ImageId": "${aws:ImageId}",
      "InstanceId": "${aws:InstanceId}",
      "InstanceType": "${aws:InstanceType}"
    },
    "metrics_collected": {
      "collectd": {
        "metrics_aggregation_interval": 60
      },
      "disk": {
        "measurement": [
          "used_percent"
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ]
      },
      "mem": {
        "measurement": [
          "mem_used_percent"
        ],
        "metrics_collection_interval": 60
      },
      "statsd": {
        "metrics_aggregation_interval": 60,
        "metrics_collection_interval": 10,
        "service_address": ":8125"
      }
    }
  }
}
EOF
    chown "$(whoami)" "$CONF_FILE"
    systemctl start amazon-cloudwatch-agent
}

function install_java_17() {
  # Install Java 17 (Correto)
  rpm --import https://yum.corretto.aws/corretto.key
  curl -s -L -o /etc/yum.repos.d/corretto.repo https://yum.corretto.aws/corretto.repo

  yum install -y java-17-amazon-corretto-devel
}

# Uses SCRIPTS_PATH variables
function update_motd() {
    cp -rf "$SCRIPTS_PATH"/setup/templates/update-motd.d/* "/etc/update-motd.d"
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
