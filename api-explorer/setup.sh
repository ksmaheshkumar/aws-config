#!/bin/sh

# This sets up packages needed on an EC2 machine for api-explorer.  This is
# based on the Ubuntu11 AMI that Amazon provides as one of the default EC2 AMI
# options. It is idempotent.
#
# This should be run as the user api-explorer.

# Typically, this is run like this
#
# $ cat setup.sh | ssh <hostname of EC2 machine> sh

# Bail on any errors
set -e

cd
CONFIG_DIR=$HOME/aws-config/api-explorer

sudo apt-get update

echo "Installing developer tools"
sudo apt-get install -y python-pip
sudo apt-get install -y git mercurial

echo "Syncing khan-api codebase"
git clone http://github.com/Khan/aws-config || ( cd aws-config && git pull )
git clone http://github.com/Khan/khan-api || ( cd khan-api && git pull )

# We don't actually create a virtualenv for the user, so this installs
# it into the system Python's dist-package directory (which requires sudo)
sudo pip install -r khan-api/explorer/requirements.txt

echo "Copying dotfiles"
for i in $CONFIG_DIR/dot_*; do
    cp "$i" ".`basename $i | sed 's/dot_//'`";
done

echo "Setting up api-explorer"
ln -snf $CONFIG_DIR/explorer.wsgi khan-api/explorer/explorer.wsgi
sudo apt-get install -y apache2 libapache2-mod-wsgi
sudo ln -snf $CONFIG_DIR/api-explorer_apache2_site \
  /etc/apache2/sites-available/api-explorer
sudo a2dissite default
sudo a2ensite api-explorer
sudo service apache2 restart

echo "Make sure ~/khan-api/explorer/secrets.py is filled out and you're done!"
echo "(And maybe a \"sudo service apache2 restart\" if you're having problems.)"
