#!/bin/sh

# This sets up packages needed on an EC2 machine for the Smarthistory Varnish
# proxy. This expects a machine created from one of the default Amazon Ubuntu
# 11.10 AMIs. It is idempotent.
#
# This should be run in the home directory of the user smarthistory.

# Typically, this is run like this
#
# $ cat setup.sh | ssh <hostname of EC2 machine> sh

# Bail on any errors
set -e

cd /home/smarthistory
CONFIG_DIR=/home/smarthistory/aws-config/smarthistory-proxy

sudo apt-get update

echo "Installing developer tools"
sudo apt-get install -y git

echo "Syncing aws-config"
git clone http://github.com/Khan/aws-config || ( cd aws-config && git pull )

echo "Copying dotfiles"
for i in $CONFIG_DIR/dot_*; do
    ln -snf "$i" ".`basename $i | sed 's/dot_//'`";
done

echo "Installing Varnish"
sudo apt-get install -y varnish
sudo ln -snf $CONFIG_DIR/varnish_default_vcl /etc/varnish/default.vcl
sudo ln -snf $CONFIG_DIR/default_varnish /etc/default/varnish
sudo /etc/init.d/varnish restart
