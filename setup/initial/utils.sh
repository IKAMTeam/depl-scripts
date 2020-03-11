#!/bin/bash

function require_root_user() {
    if [ $EUID -ne 0 ]; then
        echo "This script must be run as root user"
        exit 1
    fi
}

# Uses next variables: SCRIPTS_DIR, RELEASES_REPO_URL, SNAPSHOT_REPO_URL, REPOSITORY_UN, REPOSITORY_PWD
function checkout_depl_scripts() {
    if [ ! -d "$SCRIPTS_DIR" ]; then
        mkdir -p "$SCRIPTS_DIR"
    fi
    if [ ! -d "$SCRIPTS_DIR/.git" ]; then
        git --git-dir="$SCRIPTS_DIR/.git" --work-tree="$SCRIPTS_DIR" clone "https://github.com/IKAMTeam/depl-scripts"
    fi

    git --git-dir="$SCRIPTS_DIR/.git" --work-tree="$SCRIPTS_DIR" checkout master
    git --git-dir="$SCRIPTS_DIR/.git" --work-tree="$SCRIPTS_DIR" pull

    if [ ! -f "$SCRIPTS_DIR/credentials.conf" ]; then
        echo -e "RELEASES_REPO_URL=\"$RELEASES_REPO_URL\"\n" \
                "SNAPSHOT_REPO_URL=\"$SNAPSHOT_REPO_URL\"\n" \
                "REPOSITORY_UN=\"$REPOSITORY_UN\"\n" \
                "REPOSITORY_PWD=\"$REPOSITORY_PWD\"" > "$SCRIPTS_DIR/credentials.conf"
    fi
}
