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

# Install the "secret" (literally the text secret). The tee trick is used to
# write to the file with sudo privileges.
echo 'secret' | sudo tee "$HOME/cloudsearch_secret" > /dev/null

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
