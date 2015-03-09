#!/bin/sh

# This sets up packages needed on an EC2 machine for the Varnish proxy for
# Smarthistory and the CS JavaScript sandbox. This expects a machine created
# from one of the default Amazon Ubuntu 12.04 AMIs. It is idempotent.
#
# This should be run in the home directory of the user caching-proxy.

# Typically, this is run like this
#
# $ cat setup.sh | ssh <hostname of EC2 machine> sh

# Bail on any errors
set -e

CONFIG_DIR="$HOME"/aws-config/caching-proxy
. "$HOME"/aws-config/shared/setup_fns.sh

# These are files that would be installed because they live in
# ../shared, that you don't want installed on this machine.  e.g.
# if you really didn't want the OOM detector or foo cronjobs running
# on this machine, you could list "etc/cron.d/oom-detector.tpl etc/cron.d/foo"
SHARED_FILE_EXCLUDES=""


cd "$HOME"

update_aws_config_env       # from setup_fns.sh
install_basic_packages      # from setup_fns.sh
install_root_config_files   # from setup_fns.sh
install_user_config_files   # from setup_fns.sh
install_nginx               # from setup_fns.sh
install_varnish             # from setup_fns.sh

install_secret /etc/nginx/ssl/kasandbox.key K37         # from setup_fns.sh
install_multiline_secret /etc/nginx/ssl/kasandbox.crt F85625
