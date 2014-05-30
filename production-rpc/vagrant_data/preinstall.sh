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
echo 'secret' | sudo tee "$HOME/solr_secret" > /dev/null

# Clone the aws-config repo into our home directory (note that we're root if
# vagrant is doing the provisioning so home is probably /root). We do a copy
# here instead of a symlink so that if our provisioning scripts go crazy they
# don't thrash our network mounted repo (the one that's on our host machine!).
if [ -d "$HOME/aws-config" ]; then
	sudo rm -rf "$HOME/aws-config"
fi
sudo cp -af /var/local/aws-config "$HOME"

# On the production box it is expected that the endpoint is in ubuntu's home
# directory, so we'll do a little hackery here.
sudo ln -fs "$HOME/aws-config/production-rpc/data/cloudsearch-publish-dev-endpoint" "$HOME/aws-config/production-rpc/data/cloudsearch-publish-endpoint"
sudo chmod -R a+rx "$HOME"

# The postfix installer is going to try to grab the screen and display some
# fancy curses menu. This ends up doing some very bad things so we seed it with
# some values here.
# http://serverfault.com/questions/143968/automate-the-installation-of-postfix-on-ubuntu
debconf-set-selections <<< "postfix postfix/mailname string localhost"
debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
