# Quick setup scripts bundle

OneVizion web and app instances configuration scripts

## Table of contents
- [Setup Web/App servers](#setup-webapp-servers)
- [Setup Web/App servers on AWS platform](#setup-webapp-servers-on-aws-platform)
- [Enable SSL connection to the Oracle DB in AWS](#enable-ssl-connection-to-the-oracle-db-in-aws)
- [Upgrade Tomcat on non-AWS environment](#upgrade-tomcat-on-non-aws-environment)

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

**Example snippet for Web Server setup**:

Use `aws-setup-app-server.sh` to setup application server.


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

User Data script execution logs are available in the `/var/log/cloud-init-output.log`

Check [aws-setup.conf.template](aws-setup.conf.template) for get more info about configuration.

**Note**: You can run this snippet multiple times to install multiple websites or services on single server

**Note**: To setup Route53 record you need to specify IAM Role for EC2 Instance

This IAM Role should contains next permissions:
- `Route53:ListHostedZonesByName` - For convert hosted zone name to ID
- `Route53:ChangeResourceRecordSets` - For create record (Limit for hosted zone you use only)
- `EC2:DescribeTags` - For read `Name` tag attached to specific instance

**Note**: To prevent setup script to update Route53 record every run - set `AWS_DOMAIN` to empty value for 2+ runs


## Enable SSL connection to the Oracle DB in AWS
1. Make sure SSL is enabled in AWS RDS option group with following settings:
- Port is `2484`
- `SSL_VERSION=1.2`
- `CIPHER_SUITE=SSL_RSA_WITH_AES_256_GCM_SHA384`

2. Use instructions from https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.Oracle.Options.SSL.html to generate Java keystore file with AWS certificates:
    - Download certificate from https://s3.amazonaws.com/rds-downloads/rds-ca-2019-root.pem, then run:

        `openssl x509 -outform der -in rds-ca-2019-root.pem -out rds-ca-2019-root.der`

3. Import AWS Certificate into Java trust store (located in `$JAVA_HOME/jre/lib/security/cacerts`, also Tomcat prints out `JAVA_HOME` into logs on startup):

    `sudo keytool -import -trustcacerts -keystore cacerts -storepass <changeit> -alias Root -file rds-ca-2019-root.der`

4. Modify `web.dbSid` parameter in `ROOT.xml` to:
    
    ```
    (DESCRIPTION= (ADDRESS=(PROTOCOL=TCPS)(PORT=2484)(HOST=[placeholder for Oracle host]))(CONNECT_DATA=(SID=[placeholder for Oracle SID]))(SECURITY=(SSL_SERVER_CERT_DN="C=US,ST=Washington,L=Seattle,O=Amazon.com,OU=RDS,CN=%s")))
    ```

5. Replace `[placeholder for Oracle SID]` and `[placeholder for Oracle host]` with correct values.

## Upgrade Tomcat on non-AWS environment
1. After tomcat upgrade on non-AWS environment run `./config-tomcat-security.sh` for restore Tomcat files and directories correct permissions.
