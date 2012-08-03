#!/bin/bash
set -e # exit on error
export REPO_ROOT=$HOME/aws-config/production-rpc

echo "Stopping tomcat"
sudo /etc/init.d/tomcat6 stop

echo "Updating solr config"
sudo rm /var/lib/tomcat6/conf/Catalina/localhost/solr.xml
sudo cp $REPO_ROOT/config/solr_tomcat_context.xml /var/lib/tomcat6/conf/Catalina/localhost/solr.xml

echo "Updating solr schema"
sudo rm -r /var/lib/tomcat6/khan-solr
sudo cp -r $REPO_ROOT/solr /var/lib/tomcat6/khan-solr
sudo chown -R tomcat6:tomcat6 /var/lib/tomcat6/khan-solr

echo "Updating lighttpd config"
sudo rm /etc/lighttpd/lighttpd.conf
sudo cp $REPO_ROOT/config/lighttpd.conf /etc/lighttpd/lighttpd.conf

echo "Starting tomcat"
sudo /etc/init.d/tomcat6 start

# reindex data
$REPO_ROOT/scripts/update_solr.bash

echo "solr updated"
