# Quick setup scripts bundle

OneVizion web and app instances configuration scripts

## Table of contents
- [Setup Web/App servers](#setup-webapp-servers)
- [Setup Web/App servers on AWS platform](#setup-webapp-servers-on-aws-platform)

## Setup Web/App servers

1. Prepare instance
- Install Git
- Install Python 2.7
- Install Java 11 (Oracle or OpenJDK)
- Install Tomcat 8.5 (if you want to configure server as web instance)

2. Clone deployment scripts: `git clone -b stable https://github.com/IKAMTeam/depl-scripts.git`
3. Create and fill configuration file (check [setup-server.conf.template](setup-server.conf.template) for get info about configuration)
4. Start config script:

- Run `./setup-web-server.sh setup-server.conf` to configure server as web instance
- Run `./setup-app-server.sh setup-server.conf` to configure server as app instance

**Note**: You can run setup scripts multiple times to install multiple websites or services on single server

**Sample of `setup-server.conf`**:
```
SCRIPTS_PATH="/home/my-user/depl-scripts"
SCRIPTS_OWNER="my-user:my-user"

RELEASES_REPO_URL="https://..."
SNAPSHOT_REPO_URL="https://..."
REPOSITORY_UN="username"
REPOSITORY_PWD='password'

WEBSITE="test01.onevizion.com"
VERSION="20.5.0"

# Database credentials
DB_OWNER_USER="prod01"
DB_OWNER_PASSWORD='password'
DB_USER_PASSWORD='password'
DB_PKG_PASSWORD='password'
DB_RPT_PASSWORD='password'
DB_URL='rds.endpoint:1521:A1'

AES_PASSWORD=''

# App specific
SERVICES_PATH="/opt"

# Leave empty to omit monitoring setup
MONITOR_VERSION="2.0.8"

MONITOR_DB_USER="monitor"
MONITOR_DB_PASSWORD='password'

# Use AWS SQS to deliver monitoring statuses, leave blank for omit
MONITOR_AWS_SQS_ACCESS_KEY="[placeholder]"
MONITOR_AWS_SQS_SECRET_KEY="[placeholder]"
MONITOR_AWS_SQS_QUEUE_URL="[placeholder]"

# Email addresses to deliver monitoring warnings and errors, leave blank for omit
MONITOR_WARN_MAIL_HOST="[placeholder]"
MONITOR_WARN_MAIL_PORT="[placeholder]"
MONITOR_WARN_MAIL_USERNAME="[placeholder]"
MONITOR_WARN_MAIL_PASSWORD='[placeholder]'
MONITOR_WARN_MAIL_FROM="[placeholder]"
MONITOR_WARN_MAIL_TO="[placeholder]"

MONITOR_ERROR_MAIL_HOST="[placeholder]"
MONITOR_ERROR_MAIL_PORT="[placeholder]"
MONITOR_ERROR_MAIL_USERNAME="[placeholder]"
MONITOR_ERROR_MAIL_PASSWORD='[placeholder]'
MONITOR_ERROR_MAIL_FROM="[placeholder]"
MONITOR_ERROR_MAIL_TO="[placeholder]"

# Web specific
TOMCAT_PATH="/usr/share/tomcat"
TOMCAT_SERVICE="tomcat"
TOMCAT_UN="tomcat"
TOMCAT_GROUP="tomcat"

ENTERPRISE_EDITION="true"
```

## Setup Web/App servers on AWS platform

Using [EC2 UserData](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html)

**Requirements:**
- Amazon Linux 2 Latest AMI

**Example snippet**:
```
#!/bin/bash

SCRIPTS_PATH="/home/ec2-user/depl-scripts"
SCRIPTS_OWNER="ec2-user:ec2-user"

yum install -y git
git clone -b stable https://github.com/IKAMTeam/depl-scripts.git "$SCRIPTS_PATH"
chown "$SCRIPTS_OWNER" "$SCRIPTS_DIR"

"$SCRIPTS_PATH/setup/initial/aws-setup-web-server.sh" - <<'EOF'
# Leave empty to skip private DNS entry creation
AWS_DOMAIN='ov.internal'

SCRIPTS_PATH="/home/ec2-user/depl-scripts"
SCRIPTS_OWNER="ec2-user:ec2-user"

RELEASES_REPO_URL="https://..."
SNAPSHOT_REPO_URL="https://..."
REPOSITORY_UN="username"
REPOSITORY_PWD='password'

WEBSITE="test01.onevizion.com"
VERSION="20.5.0"

# Database credentials
DB_OWNER_USER="prod01"
DB_OWNER_PASSWORD='password'
DB_USER_PASSWORD='password'
DB_PKG_PASSWORD='password'
DB_RPT_PASSWORD='password'
DB_URL='rds.endpoint:1521:A1'

AES_PASSWORD=''

# App specific
SERVICES_PATH="/opt"

MONITOR_DB_USER="monitor"
MONITOR_DB_PASSWORD='password'

# Use AWS SQS to deliver monitoring statuses, leave blank for omit
MONITOR_AWS_SQS_ACCESS_KEY="[placeholder]"
MONITOR_AWS_SQS_SECRET_KEY="[placeholder]"
MONITOR_AWS_SQS_QUEUE_URL="[placeholder]"

# Email addresses to deliver monitoring warnings and errors, leave blank for omit
MONITOR_WARN_MAIL_HOST="[placeholder]"
MONITOR_WARN_MAIL_PORT="[placeholder]"
MONITOR_WARN_MAIL_USERNAME="[placeholder]"
MONITOR_WARN_MAIL_PASSWORD='[placeholder]'
MONITOR_WARN_MAIL_FROM="[placeholder]"
MONITOR_WARN_MAIL_TO="[placeholder]"

MONITOR_ERROR_MAIL_HOST="[placeholder]"
MONITOR_ERROR_MAIL_PORT="[placeholder]"
MONITOR_ERROR_MAIL_USERNAME="[placeholder]"
MONITOR_ERROR_MAIL_PASSWORD='[placeholder]'
MONITOR_ERROR_MAIL_FROM="[placeholder]"
MONITOR_ERROR_MAIL_TO="[placeholder]"

# Leave empty to omit monitoring setup
MONITOR_VERSION="2.0.8"

# Web specific
TOMCAT_PATH="/usr/share/tomcat"
TOMCAT_SERVICE="tomcat"
TOMCAT_UN="tomcat"
TOMCAT_GROUP="tomcat"

ENTERPRISE_EDITION="true"

EOF
```

After complete this snippet you get ready to work deployment scripts at `/home/ec2-user/depl-scripts` and installed/running Apache Tomcat with OneVizion package

**Note**: Another scripts `aws-setup-web-server.sh` and `aws-setup-app-server.sh` should be used here

Check [aws-setup.conf.template](aws-setup.conf.template) for get more info about configuration.

**Note**: You can run this snippet multiple times to install multiple websites or services on single server

**Note**: To setup Route53 record you need to specify IAM Role for EC2 Instance

This IAM Role should contains next permissions:
- `Route53:ListHostedZonesByName` - For convert hosted zone name to ID
- `Route53:ChangeResourceRecordSets` - For create record (Limit for hosted zone you use only)
- `EC2:DescribeTags` - For read `Name` tag attached to specific instance

**Note**: To prevent setup script to update Route53 record every run - set `AWS_DOMAIN` to empty value for 2+ runs
