#!/bin/bash

# This script installs nginx to reverse proxy CloudSearch.

# Echo all commands (and show values of variables)
set -x

# Stop on failure
set -e

if [ ! -s "$HOME/cloudsearch_secret" ]; then
  # The 'sudo tee' trick is the easiest way to redirect output to a file under sudo.
  echo 'Cannot install nginx without the shared secret. Run'
  echo '  echo '\''<cloudsearch_secret>'\'' | sudo tee -a "$HOME/cloudsearch_secret" > /dev/null'
  echo "Where <cloudsearch_secret> is taken from secrets.py, and run this script again."
  exit 1
fi

# This script assumes an Ubuntu 11.10 or 12.04 server.
# This git repository should be cloned into $HOME/aws-config.
REPO_ROOT="$HOME/aws-config/production-rpc"

# We need nginx as well, which we pull from a PPA because we need a more recent
# version than the default in 12.04.
sudo apt-get -y install python-software-properties
sudo add-apt-repository -y "deb http://ppa.launchpad.net/nginx/stable/ubuntu `lsb_release -cs` main"
sudo apt-get update
sudo apt-get -y install nginx

# Remove any default configuration that the dpkg installed
sudo rm -f /etc/nginx/sites-available/default /etc/nginx/sites-available/default

# Process the nginx configuration with sed, nature's templating engine
SITES_AVAILABLE="$REPO_ROOT/etc/nginx/sites-available"
sed -e s,{{SECRET}},`cat "$HOME/cloudsearch_secret"`,g \
	-e s,{{CLOUDSEARCH_DOCUMENT_ENDPOINT}},`cat "$REPO_ROOT/data/cloudsearch-publish-endpoint"`,g \
	-e s,{{CLOUDSEARCH_DOCUMENT_ENDPOINT_2}},`cat "$REPO_ROOT/data/cloudsearch-publish-endpoint-2"`,g \
	< "$REPO_ROOT/etc/nginx/sites-available/search.conf.in" \
	> /etc/nginx/sites-available/search.conf

sed -e s,{{HOME}},"$HOME", \
    < "$REPO_ROOT/etc/nginx/sites-available/graphie-to-png.conf.in" \
    > /etc/nginx/sites-available/graphie-to-png.conf

# Set up the top-level nginx configuration
ln -snf "$REPO_ROOT/etc/nginx/nginx.conf" /etc/nginx/nginx.conf

# Configure nginx
for f in /etc/nginx/sites-available/*.conf; do
    sudo ln -snfv "$f" /etc/nginx/sites-enabled/

    # Make sure that the server that we're using actually resolve.
    nginx_hostname=`sed -n 's/^ *server_name //p' $f | tr -d ';'`
    if [ -n "$nginx_hostname" ]; then
        host "$nginx_hostname" >/dev/null 2>&1 || {
            echo "$f listens on $nginx_hostname but that host does not resolve."
            echo "You should set it up as an A or CNAME on ec2."
            echo "Hit <enter> to continue"
            read prompt
        }
    fi
done

# Restart nginx to pick up our changes
sudo /etc/init.d/nginx restart
