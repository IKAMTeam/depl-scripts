#!/bin/bash
### Script for check Tomcat directory for *.rpmnew files and warn user if exists ###

# shellcheck source=../../utils.sh
. "$(dirname "$0")/../../utils.sh"

require_root_user

RPMNEW_FILES=$(find "$TOMCAT_PATH" -name '*.rpmnew' -type f)

if [ -n "$RPMNEW_FILES" ]; then
    echo "WARNING!!! the following files were modified during upgrade and should be reviewed and merged with original files containing OneVizion modification:"
    echo "$RPMNEW_FILES"
fi
