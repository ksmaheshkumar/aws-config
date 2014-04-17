#!/bin/sh

# This has files that are used on our production-rpc server, that runs on
# ec2.  It has things that are needed for our production services,
# such as search.
#
# Note that solr setup is done separately from this file, via
# install_solr.bash and update_solr_config.bash.
# (TODO(csilvers): remove this comment once we've removed use of solr.)
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

# Make sure we have the most recent info for apt.
sudo apt-get update

install_basic_packages() {
    echo "Installing packages: Basic setup"
    sudo apt-get install -y ntp
    sudo apt-get install -y gcc
    sudo apt-get install -y make
    # This is needed so installing postfix doesn't prompt.  See
    # http://www.ossramblings.com/preseed_your_apt_get_for_unattended_installs
    # If it prompts anyway, type in the stuff from postfix.preseed manually.
    sudo apt-get install -y debconf-utils
    sudo debconf-set-selections aws-config/production-rpc/postfix.preseed
    sudo apt-get install -y postfix

    echo "(Finishing up postfix config)"
    sudo sed -i -e 's/myorigin = .*/myorigin = khanacademy.org/' \
                -e 's/myhostname = .*/myhostname = prod-rpc.khanacademy.org/' \
                -e 's/inet_interfaces = all/inet_interfaces = loopback-only/' \
                /etc/postfix/main.cf
    sudo service postfix restart
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

install_root_config_files() {
    echo "Updating config files on the root filesystem (using symlinks)"

    sudo cp -sav --backup=numbered "$HOME/aws-config/production-rpc/etc/" /
    sudo chown root:root /etc

    # Stuff in /etc/init needs to be owned by root, so we copy instead of
    # symlinking there.
    find /etc/init -type l | sudo xargs rm
    sudo install -m644 "$HOME"/aws-config/production-rpc/etc/init/* /etc/init
}

install_user_config_files() {
    echo "Updating dotfiles (using symlinks)"
    for dotfile in "$HOME"/aws-config/production-rpc/.[!.]*; do
        ln -snfv "$dotfile"
    done
}

start_daemons() {
    echo "Starting daemons in $HOME/aws-config/internal-webserver/etc/init"
    for daemon in $HOME/aws-config/production-rpc/etc/init/*.conf; do
        sudo stop `basename $daemon .conf` || true
        sudo start `basename $daemon .conf`
    done
}


cd "$HOME"
install_basic_packages
install_repositories
install_root_config_files
install_user_config_files

# Do this again, just in case any of the apt-get installs nuked it.
install_root_config_files

# Start the daemons!
start_daemons
