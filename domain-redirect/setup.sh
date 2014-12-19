#!/bin/sh

# This sets up packages needed on an EC2 machine to run a simple
# 'naked redirect' (khanacademy.org -> www.khanacademy.org).  This
# expects a machine created from one of the default Amazon Ubuntu
# 12.04 AMIs. It is idempotent.
#
# This should be run in the home directory of the user ubuntu.

# Typically, this is run like this
#
# $ cat setup.sh | ssh <hostname of EC2 machine> sh

# Bail on any errors
set -e

CONFIG_DIR="$HOME"/aws-config/domain-redirect
. "$HOME"/aws-config/shared/setup_fns.sh

cd "$HOME"

update_aws_config_env       # from setup_fns.sh
install_basic_packages      # from setup_fns.sh
install_root_config_files   # from setup_fns.sh
install_nginx               # from setup_fns.sh

if [ ! -s "/etc/nginx/ka-wild-13.key" ]; then
    echo "To finish setting up nginx, copy the secret at"
    echo "   https://phabricator.khanacademy.org/K35"
    echo "to"
    echo "   /etc/nginx/ka-wild-13.key"
    echo "and from"
    echo "   https://phabricator.khanacademy.org/F85633"
    echo "(which is mentioned in the description of K35) to"
    echo "   /etc/nginx/ka-wild-13.crt"
    echo "(as root) and then chmod 600 /etc/nginx/ka-wild-13.*"
    echo "Hit enter when done:"
    read prompt
fi
