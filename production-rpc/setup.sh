#!/bin/sh

# This has files that are used on our production-rpc server, that runs on
# ec2.  It has things that are needed for our production services,
# such as search.
#
# NOTE: to run udp-relay, the aws machine's firewall must be set up to
# pass through UDP packets on ports 2003 and 2004.

# Typically, this is run like this
#
# $ cat setup.sh | ssh <hostname of EC2 machine> bash
#
# WARNING: We've never actually tried to run this script all the way
# through!  Even if it works perfectly, it may still have manual
# steps.  You should definitely be careful running it the first time,
# and treat it more like a README than something you can just run and
# forget.


# Bail on any errors
set -e

CONFIG_DIR="$HOME/aws-config/production-rpc"
. "$HOME/aws-config/shared/setup_fns.sh"


install_basic_packages_prodrpc() {
    echo "Installing packages: Basic setup"
    sudo apt-get install -y gcc make

    # Rest is standard
    install_basic_packages    # from setup_fns.sh
}

install_repositories() {
    echo "Syncing udp-relay codebase"
    sudo apt-get install -y git
    git clone git://github.com/Khan/udp-relay || \
        ( cd udp-relay && git pull )
    # Now compile udp-relay
    ( cd udp-relay && make )

    # Make sure the necessary secrets file is there
    if [ ! -s "$HOME/relay.secret" ]; then
        echo "You must install $HOME/relay.secret.  To do this, do"
        echo "   echo <hostedgraphite_api_key> > $HOME/relay.secret"
        echo "   chmod 600 $HOME/relay.secret"
        echo "Where <hostedcrowdin-api-key> is from webapp's secrets.py."
        echo "Hit enter when done..."
        read prompt
    fi
}


cd "$HOME"
update_aws_config_env              # from setup_fns.sh
install_basic_packages_prodrpc
install_repositories
install_root_config_files          # from setup_fns.sh
install_user_config_files          # from setup_fns.sh

# Start the daemons!
start_daemons                      # from setup_fns.sh
