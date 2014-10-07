#!/bin/sh

# This sets up our youtube-export machine on an EC2 Ubuntu12 AMI.
#
# Idempotent.  Run this as the ubuntu user.
#
# This can be run like
#
# $ cat setup.sh | ssh ubuntu@<hostname of EC2 machine> sh

# Bail on any errors
set -e

CONFIG_DIR="$HOME"/aws-config/youtube-export
. "$HOME"/aws-config/shared/setup_fns.sh

cd "$HOME"

install_repositories() {
    echo "Syncing youtube-export codebase"
    sudo apt-get install -y git
    git clone git://github.com/Khan/youtube-export || \
        ( cd youtube-export && git pull && git submodule update --init --recursive )
    # We don't set up virtualenv on this machine, so just install into /usr.
    sudo pip install -r youtube-export/requirements.txt
}

update_aws_config_env          # from setup_fns.sh
install_basic_packages         # from setup_fns.sh
install_root_config_files      # from setup_fns.sh
install_user_config_files      # from setup_fns.sh
install_repositories
install_crontab                # from setup_fns.sh

if [ ! -s "$HOME"/s3_secret_key ]; then
    echo "Run the following commands to set up the s3 secrets,"
    echo "where the values in braces are taken from webapp's secrets.py."
    echo "   echo '<youtube_export_s3_access_key>' > ~/s3_access_key"
    echo "   echo '<youtube_export_s3_secret_key>' > ~/s3_secret_key"
    echo "   chmod 600 ~/s3_*"
    echo "Hit <enter> when this is done:"
    read prompt
fi

