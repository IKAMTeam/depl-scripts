# Quick setup scripts bundle

Use this scripts for quick build App and Web servers

## Table of contents
- [Setup Web/App servers](#setup-webapp-servers)
- [Setup Web/App servers on AWS platform](#setup-webapp-servers-on-aws-platform)

## Setup Web/App servers

**Note**: You can run this snippet multiple times for install multiple websites or services on single server

## Setup Web/App servers on AWS platform

Quick way to setup OneVizion App/Web packages to AWS is to run installation code from [EC2 Instance UserData](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html)

**Requirements:**
- Amazon Linux 2 Latest AMI

**Example snippet**:
```
SCRIPTS_DIR="/home/ec2-user/depl-scripts"
SCRIPTS_OWNER="ec2-user"

yum install -y git
git clone https://github.com/IKAMTeam/depl-scripts.git "$SCRIPTS_DIR"
chown "$SCRIPTS_OWNER" "$SCRIPTS_DIR"

"$SCRIPTS_DIR/setup/initial/aws-setup-web-server.sh" - <<EOF
AWS_DOMAIN='ov.internal'

SCRIPTS_DIR="/home/ec2-user/depl-scripts"
SCRIPTS_OWNER="ec2-user"

RELEASES_REPO_URL="https://..."
SNAPSHOT_REPO_URL="https://..."
REPOSITORY_UN="username"
REPOSITORY_PWD='password'

WEBSITE="test01.onevizion.com"
VERSION="20.5.0"

DB_OWNER_USER="prod01"
DB_OWNER_PASSWORD='password'
DB_USER_PASSWORD='password'
DB_PKG_PASSWORD='password'
DB_RPT_PASSWORD='password'
DB_URL='rds.endpoint:1521:A1'

AES_PASSWORD=''

DB_MONITOR_USER="monitor"
DB_MONITOR_PASSWORD='password'
MONITORING_VERSION="2.0.8"

# Web specific
TOMCAT_DIR="/usr/share/tomcat"
TOMCAT_SERVICE="tomcat"

ENTERPRISE_EDITION="true"

EOF
```

After complete this snippet you get ready to work deployment scripts at `/home/ec2-user/depl-scripts` and installed/running Apache Tomcat with OneVizion package.

**Note**: Another scripts `aws-setup-web-server.sh` and `aws-setup-app-server.sh` should be used here.

**Note**: You can run this snippet multiple times for install multiple websites or services on single server

**Note**: For setup Route53 record set you need to specify IAM Role for EC2 Instance.

This IAM Role should contains next permissions:
- `Route53:ListHostedZonesByName` - For convert hosted zone name to ID
- `Route53:ChangeResourceRecordSets` - For create record (Limit for hosted zone you use only)
- `EC2:DescribeTags` - For read `url-internal` tag attached to specific instance
