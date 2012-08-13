#!/bin/sh

# This sets up packages needed on an EC2 machine for analytics
# This is based on the Ubuntu11 AMI that Amazon provides as one of
# the default EC2 AMI options. It is idempotent.
#
# This should be run in the home directory of the role account
# of the user that is to run the analytics jobs.

# Typically, this is run like this
#
# $ cat setup.sh | ssh <hostname of EC2 machine> sh

# Bail on any errors
set -e

sudo apt-get update

echo "Installing lighttpd proxy"
sudo apt-get install -y lighttpd
sudo mkdir $HOME/log/lighttpd
sudo chown -R www-data:www-data $HOME/log/lighttpd
sudo ln -snf $HOME/aws-config/cs-proxy/etc/lighttpd/lighttpd.conf /etc/lighttpd/
sudo service lighttpd restart
