#!/usr/bin/env bash

# This file is run by Vagrant during the provisioning process. See the
# Vagrantfile in production-rpc.

# Echo all commands (and show values of variables)
set -x

# Stop on failure
set -e

# Refresh our indexes. Any installations will almost certainly fail if we don't
# do this after brining up an image.
sudo apt-get -y update

sudo apt-get -y install git

# Install the "secret" (literally the text secret). The tee trick is given in
# install_solr.bash and is used to write to the file with sudo privileges
sudo mkdir -p /etc/lighttpd
echo 'var.secret = "secret"' | sudo tee /etc/lighttpd/khan-secret.conf > /dev/null

# Clone the aws-config repo into our home directory
cd
if [ ! -d "aws-config/" ]; then
	git clone git://github.com/Khan/aws-config
fi

# The postfix installer is going to try to grab the screen and display some
# fancy curses menu. This ends up doing some very bad things so we seed it with
# some values here.
# http://serverfault.com/questions/143968/automate-the-installation-of-postfix-on-ubuntu
debconf-set-selections <<< "postfix postfix/mailname string localhost"
debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
