#!/bin/sh

# This sets up packages needed on an EC2 machine for sandcastle. This is based
# on the Ubuntu11 AMI that Amazon provides as one of the default EC2 AMI
# options. It is idempotent.
#
# This should be run in the home directory of the user sandcastle.

# Typically, this is run like this
#
# $ cat setup.sh | ssh <hostname of EC2 machine> sh

# Bail on any errors
set -e

CONFIG_DIR="$HOME"/aws-config/sandcastle
. "$HOME"/aws-config/shared/setup_fns.sh

cd "$HOME"


install_repositories() {
    echo "Syncing youtube-export codebase"
    sudo apt-get install -y git
    git clone git://github.com/Khan/sandcastle || \
        ( cd sandcastle && git pull && git submodule update --init --recursive )
    # We don't set up virtualenv on this machine, so just install into /usr.
    sudo pip install -r youtube-export/requirements.txt
}

install_arcanist() {
    echo "Setting up arcanist"
    sudo apt-get install -y php5-cli php5-curl
    git clone http://github.com/Khan/arcanist.git || ( cd arcanist && git pull )
    git clone http://github.com/Khan/libphutil.git || ( cd libphutil && git pull )
}

setup_sandcastle() {
    echo "Setting up sandcastle"
    mkdir -p sandcastle/apache
    ln -snf $CONFIG_DIR/sandcastle_apache_django.wsgi sandcastle/apache/django.wsgi
    ln -snf $CONFIG_DIR/sandcastle_local_settings.py sandcastle/local_settings.py

    rm -f sandcastle/*.sqlite3
    python sandcastle/manage.py syncdb

    git clone http://github.com/Khan/khan-exercises.git sandcastle/media/repo || \
        ( cd sandcastle/media/repo/khan-exercises && git pull && git submodule update --init --recursive )
}

install_apache() {
    sudo apt-get install -y apache2 libapache2-mod-wsgi
    sudo ln -snf $CONFIG_DIR/sandcastle_apache2_ports.conf \
        /etc/apache2/ports.conf
    sudo ln -snf $CONFIG_DIR/sandcastle_apache2_site \
        /etc/apache2/sites-available/sandcastle
    sudo ln -snf $CONFIG_DIR/sandcastle_apache2_envvars \
        /etc/apache2/envvars
    sudo a2enmod rewrite
    sudo a2dissite default
    sudo a2ensite sandcastle
    sudo service apache2 restart
}


update_aws_config_env          # from setup_fns.sh
install_basic_packages         # from setup_fns.sh
install_root_config_files      # from setup_fns.sh
install_user_config_files      # from setup_fns.sh
install_arcanist
install_repositories
setup_sandcastle
install_apache

if [ ! -s "$HOME"/.arcrc ]; then
    echo "To finish setting up arc, copy sandcastle_dot_arcrc from"
    echo "   https://www.dropbox.com/home/Khan%20Academy%20All%20Staff/Secrets"
    echo "to"
    echo "   $HOME/.arcrc"
    echo "and then chmod to 600"
    echo "Hit enter when done:"
    read prompt
fi

# TODO(alpert): better sandcastle logging setup
