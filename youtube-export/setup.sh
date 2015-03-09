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

# These are files that would be installed because they live in
# ../shared, that you don't want installed on this machine.  e.g.
# if you really didn't want the OOM detector or foo cronjobs running
# on this machine, you could list "etc/cron.d/oom-detector.tpl etc/cron.d/foo"
SHARED_FILE_EXCLUDES=""

cd "$HOME"

install_repositories() {
    echo "Syncing youtube-export codebase"
    sudo apt-get install -y git
    clone_or_update git://github.com/Khan/youtube-export
    # We don't set up virtualenv on this machine, so just install into /usr.
    sudo pip install -r youtube-export/requirements.txt
}

update_aws_config_env          # from setup_fns.sh
install_basic_packages         # from setup_fns.sh
install_root_config_files      # from setup_fns.sh
install_user_config_files      # from setup_fns.sh
install_repositories
install_crontab                # from setup_fns.sh

install_secret_from_secrets_py "$HOME/s3_access_key" youtube_export_s3_access_key
install_secret_from_secrets_py "$HOME/s3_secret_key" youtube_export_s3_secret_key
install_secret_from_secrets_py "$HOME/zencoder_api_key" zencoder_api_key
