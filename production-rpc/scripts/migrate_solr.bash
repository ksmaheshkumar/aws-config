#!/bin/bash
export REPO_ROOT=$HOME/aws-config/production-rpc

sudo /etc/init.d/tomcat6 stop

sudo rm /var/lib/tomcat6/conf/Catalina/localhost/solr.xml
sudo cp $REPO_ROOT/config/solr_tomcat_context.xml /var/lib/tomcat6/conf/Catalina/localhost/solr.xml

sudo rm -r /var/lib/tomcat6/khan-solr
sudo cp -r $REPO_ROOT/solr /var/lib/tomcat6/khan-solr
sudo chown -R tomcat6:tomcat6 /var/lib/tomcat6/khan-solr

sudo rm /etc/lighttpd/lighttpd.conf
sudo cp $REPO_ROOT/config/lighttpd.conf /etc/lighttpd/lighttpd.conf

sudo /etc/init.d/tomcat6 start
