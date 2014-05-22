#!/bin/bash

# This script installs Tomcat and Solr/Lucene for search indexing of the
# KhanAcademy.org content. This will blow away any configuration changes you've
# made to the nginx configuration. This script attempts to be idempotent.

# Echo all commands (and show values of variables)
set -x

# Stop on failure
set -e

if [ ! -s "$HOME/solr_secret" ]; then
  # The 'sudo tee' trick is the easiest way to redirect output to a file under sudo.
  echo 'Cannot install Solr without the shared secret. Run'
  echo '  echo '\''<solr_secret>'\'' | sudo tee -a "$HOME/solr_secret" > /dev/null'
  echo "Where <solr_secret> is taken from secrets.py, and run this script again."
  exit 1
fi

# This script assumes an Ubuntu 11.10 or 12.04 server.
# This git repository should be cloned into $HOME/aws-config.
REPO_ROOT="$HOME/aws-config/production-rpc"
SCRIPT_ROOT="$REPO_ROOT/scripts"
SOLR_VERSION='3.6.0'
ARCHIVE_URL="http://archive.apache.org/dist/lucene/solr/$SOLR_VERSION/apache-solr-$SOLR_VERSION.tgz"

# chdir to $REPO_ROOT
cd "$REPO_ROOT"

# Start out by installing package dependencies
sudo apt-get -y install tomcat6 curl mailutils moreutils

# Configure Tomcat: Set port number to 9001
sudo sed -i 's/8080/9001/g' '/var/lib/tomcat6/conf/server.xml'

# Download the solr archive if we don't already have a copy.
DOWNLOAD=1
if [ -e "$HOME/apache-solr.tgz" ]; then
	# Grabs the checksum from the remote site to check if we have the archive
	REMOTE_CHECKSUM=$(curl "$ARCHIVE_URL.md5" | awk '{ print $1 }')
	LOCAL_CHECKSUM=$(md5sum "$HOME/apache-solr.tgz" | awk '{ print $1 }')
	if [[ "$REMOTE_CHECKSUM" == "$LOCAL_CHECKSUM" ]]; then
		DOWNLOAD=0
	fi
fi

if [[ "$DOWNLOAD" == 1 ]]; then
	curl "$ARCHIVE_URL" > "$HOME/apache-solr.tgz"
fi

# Extract the archive into our current directory, rip out the .war file, and
# delete the rest.
tar -xf "$HOME/apache-solr.tgz"
cp "apache-solr-$SOLR_VERSION/dist/apache-solr-$SOLR_VERSION.war" "$REPO_ROOT/solr/solr.war"
rm -rf "apache-solr-$SOLR_VERSION"

# Copy configuration data
sudo cp "$REPO_ROOT/config/solr_tomcat_context.xml" "/var/lib/tomcat6/conf/Catalina/localhost/solr.xml"

# Copy Solr app directory outside of $HOME
sudo cp -r "$REPO_ROOT/solr" /var/lib/tomcat6/khan-solr

# Set permissions so that Tomcat can read the files
sudo chown -R tomcat6:tomcat6 /var/lib/tomcat6/khan-solr

# Delete the default Tomcat index page
sudo rm -f /var/lib/tomcat6/webapps/ROOT/index.html

# Restart Tomcat server to pick up our changes
sudo /etc/init.d/tomcat6 restart

# We need nginx as well, which we pull from a PPA
sudo apt-get -y install python-software-properties
sudo add-apt-repository -y "deb http://ppa.launchpad.net/nginx/stable/ubuntu `lsb_release -cs` main"
sudo apt-get update
sudo apt-get -y install nginx

# Remove any default configuration that the dpkg installed
sudo rm -f /etc/nginx/sites-available/default /etc/nginx/sites-available/default

# Process the nginx configuration with sed, nature's templating engine
SITES_AVAILABLE="$REPO_ROOT/etc/nginx/sites-available"
sed -e s,{{SECRET}},`cat "$HOME/solr_secret"`,g \
	-e s,{{CLOUDSEARCH_DOCUMENT_ENDPOINT}},`cat "$REPO_ROOT/data/cloudsearch-publish-endpoint"`,g \
	< "$REPO_ROOT/etc/nginx/sites-available/search.conf.in" \
	> /etc/nginx/sites-available/search.conf

# Set up the top-level nginx configuration
ln -snf "$REPO_ROOT/etc/nginx/nginx.conf" /etc/nginx/nginx.conf

# Configure nginx
sudo ln -snf /etc/nginx/sites-available/search.conf /etc/nginx/sites-enabled/search.conf

# Restart nginx to pick up our changes
sudo /etc/init.d/nginx restart
