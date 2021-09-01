#!/bin/bash
### Script for configure Tomcat filesystem security ###

# shellcheck source=utils.sh
. "$(dirname "$0")/utils.sh"

require_root_user

# Remove unresolvable symbolic links to prevent 'cannot dereference' error from chown/chmod
find -L "$TOMCAT_PATH" -type l -exec sh -c 'realpath "$1" &> /dev/null || (echo "Removing $1"; rm -f "$1")' -- {} +

chown -LR "$(whoami):$TOMCAT_GROUP" "$TOMCAT_PATH" || exit 1
find -L "$TOMCAT_PATH" -type d -exec chmod g+r,g-w,g+s,g+x,o-r,o-w,o-x {} + || exit 1
find -L "$TOMCAT_PATH" -type f -exec chmod g+r,g-w,o-r,o-w,o-x {} + || exit 1
find "$TOMCAT_PATH"/* -maxdepth 1 -type d \( -name 'css' -or -name 'img' \) -exec chmod -R g+w {} + || exit 1
chmod -R g+w "$TOMCAT_PATH/logs" "$TOMCAT_PATH/temp" "$TOMCAT_PATH/work" || exit 1

setfacl -LRd -m u::rwx "$TOMCAT_PATH" || exit 1
setfacl -LRd -m g::r-x "$TOMCAT_PATH" || exit 1
setfacl -LRd -m o::--- "$TOMCAT_PATH" || exit 1
setfacl -LRd -m g::rwx "$TOMCAT_PATH/logs" "$TOMCAT_PATH/temp" "$TOMCAT_PATH/work" || exit 1

echo "Permissions successfully set"
