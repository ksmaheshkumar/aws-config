#!/bin/bash

# This script installs Tomcat and Solr/Lucene for search indexing of the
# KhanAcademy.org content.

if [ ! -f /etc/lighttpd/khan-secret.conf ]; then
  # The 'sudo tee' trick is the easiest way to redirect output to a file under sudo.
  echo 'Cannot install SOLR without the shared secret. Run'
  echo '  echo '\''var.secret = "<solr_secret>"'\'' | sudo tee -a /etc/lighttpd/khan-secret.conf > /dev/null'
  echo "Where <solr_secret> is taken from secrets.py"
  exit 0
fi


# This script assumes an Ubuntu 11.10 or 12.04 server.
# This git repository should be cloned into $HOME/aws-config.
export REPO_ROOT=$HOME/aws-config/production-rpc
export SCRIPT_ROOT=$REPO_ROOT/scripts
export SOLR_VERSION=3.6.0

# chdir to $REPO_ROOT
cd $REPO_ROOT

# Start out by installing package dependencies
sudo apt-get install lighttpd tomcat6 curl mailutils moreutils

# Configure Tomcat: Set port number to 9001
sudo sed -i 's/8080/9001/g' /var/lib/tomcat6/conf/server.xml

# Download and extract the Solr .war file
curl http://apache.tradebit.com/pub/lucene/solr/$SOLR_VERSION/apache-solr-$SOLR_VERSION.tgz > $REPO_ROOT/apache-solr.tgz
tar -xf $REPO_ROOT/apache-solr.tgz
cp apache-solr-$SOLR_VERSION/dist/apache-solr-$SOLR_VERSION.war $REPO_ROOT/solr/solr.war
rm -rf apache-solr-$SOLR_VERSION
rm $REPO_ROOT/apache-solr.tgz

# Copy configuration data
sudo cp $REPO_ROOT/config/solr_tomcat_context.xml /var/lib/tomcat6/conf/Catalina/localhost/solr.xml

# Copy Solr app directory outside of $HOME
sudo cp -r $REPO_ROOT/solr /var/lib/tomcat6/khan-solr

# Set permissions so that Tomcat can read the files
sudo chown -R tomcat6:tomcat6 /var/lib/tomcat6/khan-solr

# Delete the default Tomcat index page
sudo rm /var/lib/tomcat6/webapps/ROOT/index.html

# Restart Tomcat server to pick up our changes
sudo /etc/init.d/tomcat6 restart

# Configure lighttpd to redirect requests:
#   search-rpc.khanacademy.org => localhost:9001 (Tomcat)
sudo rm /etc/lighttpd/lighttpd.conf
sudo cp $REPO_ROOT/config/lighttpd.conf /etc/lighttpd/lighttpd.conf

# Restart lighttpd to pick up our changes
sudo /etc/init.d/lighttpd restart
