#!/bin/bash
if [ "$#" -ne 1 ]; then
    echo "### Script for configure Tomcat filesystem security ###"
    echo "Usage: $(basename "$0") <tomcat path>"
    echo " "
    echo "Example: $(basename "$0") /opt/tomcat"
    exit 1
fi

# shellcheck source=utils.sh
. "$(dirname "$0")/utils.sh"

require_root_user

TOMCAT_PATH=$1

chown -LR "$(whoami):$TOMCAT_GROUP" "$TOMCAT_PATH" || exit 1
(find -L "$TOMCAT_PATH" -type d -print0 | xargs -0 chmod g-w,g+s,g+x,o-r,o-w,o-x) || exit 1
(find -L "$TOMCAT_PATH" -type f -print0 | xargs -0 chmod g-w,o-r,o-w,o-x) || exit 1
(find "$TOMCAT_PATH" -maxdepth 1 -type d -name 'css' -print0 | xargs -0 chmod g+w) || exit 1
chmod -R g+w "$TOMCAT_PATH/logs" "$TOMCAT_PATH/temp" "$TOMCAT_PATH/work" || exit 1

setfacl -LRd -m u::rwx "$TOMCAT_PATH" || exit 1
setfacl -LRd -m g::r-x "$TOMCAT_PATH" || exit 1
setfacl -LRd -m o::--- "$TOMCAT_PATH" || exit 1
setfacl -LRd -m g::rwx "$TOMCAT_PATH/logs" "$TOMCAT_PATH/temp" "$TOMCAT_PATH/work" || exit 1

echo "Permissions successfully set"
