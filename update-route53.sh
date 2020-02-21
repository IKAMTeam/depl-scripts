#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

# This script will get the url-internal tag of the instance from EC2 and use it
# in Route53 for an A record and update the hostname on the machine and hosts file.

# Setup scratch directory for temp files
#  Ensures that when the script exits the
#  the temp directory is removed.
SCRATCH=$(mktemp -d -t ref.XXXXXXXXXX)
function finish {
  rm -rf "$SCRATCH"
}
trap finish EXIT

# Set this as the domain to update.
# If using other AWS CLI profile then change here
# Get other variables
DOMAIN="ov.internal"
ZONEID=$(aws route53 list-hosted-zones-by-name --dns-name ${DOMAIN} --max-items 1 | grep '"Id": "' | sed 's/^[[:space:]]*"Id": "\/hostedzone\///g' | sed 's/",//g')
EC2_REGION=$(/opt/aws/bin/ec2-metadata -z | cut -d ' ' -f2 | sed 's/[a-z]$//')
INSTANCE_ID=$(/opt/aws/bin/ec2-metadata -i | cut -d ' ' -f2)

# Get the hostname from the url-internal key
HOSTNAME=$(aws ec2 describe-tags --output text --region "${EC2_REGION}" \
--filters "Name=resource-type,Values=instance" "Name=resource-id,Values=${INSTANCE_ID}" "Name=key,Values=url-internal" | grep "${INSTANCE_ID}" | cut -f5) || true

# Exit if HOSTNAME is blank
if [[ ${#HOSTNAME} = 0 ]]; then
    echo "Cannot find a valid url-internal tag on this instance."
    exit 1
fi

# Get the internal IP address of this instance
IPV4=$(/opt/aws/bin/ec2-metadata -o | cut -d ' ' -f2)

# Build update json file
cat<<EOF > "$SCRATCH/update_dns.json"
{
  "Comment": "Updating internal URL.",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${HOSTNAME}.${DOMAIN}",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [
          {
            "Value": "${IPV4}"
          }
        ]
      }
    }
  ]
}
EOF

# Create a new A record on Route 53, replacing the old entry if nessesary
aws route53 change-resource-record-sets --hosted-zone-id "$ZONEID" --change-batch "file://$SCRATCH/update_dns.json"
