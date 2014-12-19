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

cd "$HOME"

update_aws_config_env       # from setup_fns.sh
install_basic_packages      # from setup_fns.sh
install_root_config_files   # from setup_fns.sh
install_user_config_files   # from setup_fns.sh
install_nginx               # from setup_fns.sh
install_varnish             # from setup_fns.sh

if [ ! -s /etc/nginx/ssl/kasandbox.key ]; then
    echo "To finish setting up nginx, copy the secret at"
    echo "   https://phabricator.khanacademy.org/K37"
    echo "to"
    echo "   /etc/nginx/ssl/kasandbox.key"
    echo "and from"
    echo "   https://phabricator.khanacademy.org/F85625"
    echo "(which is mentioned in the description of K37) to"
    echo "   /etc/nginx/ssl/kasandbox.crt"
    echo "(as root) and then chmod 600 /etc/nginx/ssl/*"
    echo "Hit enter when done:"
    read prompt
fi
