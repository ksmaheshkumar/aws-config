production-rpc-webserver
========================

Production RPC servers for Khan Academy website features hosted in EC2.

To install the Solr search server, run the scripts/install\_solr.bash script from the command line.

Solr:
=====

The configuration files in the solr/ directory are based on the 3.6.0 distribution of Solr (not included), available here:

http://archive.apache.org/dist/lucene/solr/3.6.0/apache-solr-3.6.0.tgz

The solr.xml file and the conf/ directory come from the example in apache-solr-3.6.0/example/solr, with a number of modifications made to the schema.xml file to handle the fields we want to index.

The solr.war file comes from apache-solr-3.6.0/dist/apache-solr-3.6.0.war.
