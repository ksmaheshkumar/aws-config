#!/usr/bin/env bash

# This file is run by Vagrant during the provisioning process. See the
# Vagrantfile in production-rpc.

# Echo all commands (and show values of variables)
set -x

# Stop on failure
set -e

# Fix the host in the nginx configuration file
sed -i 's/search-rpc.khanacademy.org/localhost/g' '/etc/nginx/sites-available/search.conf'

sudo /etc/init.d/nginx testconfig
sudo /etc/init.d/nginx reload
