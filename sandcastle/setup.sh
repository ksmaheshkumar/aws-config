#!/bin/sh

# This sets up packages needed on an EC2 machine for sandcastle. This is based
# on the Ubuntu11 AMI that Amazon provides as one of the default EC2 AMI
# options. It is idempotent.
#
# This should be run in the home directory of the user sandcastle.

# Typically, this is run like this
#
# $ cat setup.sh | ssh <hostname of EC2 machine> sh

# Bail on any errors
set -e

cd /home/sandcastle
CONFIG_DIR=/home/sandcastle/aws-config/sandcastle

sudo apt-get update

echo "Installing developer tools"
sudo apt-get install -y python-pip
sudo apt-get install -y git mercurial

echo "Syncing sandcastle codebase"
git clone http://github.com/Khan/aws-config || ( cd aws-config && git pull )
git clone http://github.com/Khan/sandcastle || ( cd sandcastle && git pull )

# We don't actually create a virtualenv for the user, so this installs
# it into the system Python's dist-package directory (which requires sudo)
sudo pip install -r sandcastle/requirements.txt

echo "Copying dotfiles"
for i in $CONFIG_DIR/dot_*; do
    cp "$i" ".`basename $i | sed 's/dot_//'`";
done

echo "Installing postfix (along with pre-requisites)"
# This is needed so installing postfix doesn't prompt.  See
# http://www.ossramblings.com/preseed_your_apt_get_for_unattended_installs
sudo apt-get install -y debconf-utils
sudo debconf-set-selections $CONFIG_DIR/postfix.preseed
sudo apt-get install -y postfix

echo "Setting up postfix config"
sudo sed -i -e 's/myorigin = .*/myorigin = khanacademy.org/' \
            -e 's/myhostname = .*/myhostname = sandcastle.khanacademy.org/' \
            -e 's/inet_interfaces = all/inet_interfaces = loopback-only/' \
            /etc/postfix/main.cf
sudo service postfix restart

echo "Setting up arcanist"
sudo apt-get install -y php5-cli php5-curl
git clone http://github.com/Khan/arcanist.git || ( cd arcanist && git pull )
git clone http://github.com/Khan/libphutil.git || ( cd libphutil && git pull )

echo "Setting up sandcastle"
mkdir -p sandcastle/apache
ln -snf $CONFIG_DIR/sandcastle_apache_django.wsgi sandcastle/apache/django.wsgi
ln -snf $CONFIG_DIR/sandcastle_local_settings.py sandcastle/local_settings.py

rm -f sandcastle/*.sqlite3
python sandcastle/manage.py syncdb

git config --global user.email "sandcastle@khanacademy.org"
git config --global user.name "sandcastle"

git clone http://github.com/Khan/khan-exercises.git \
  sandcastle/media/repo || true

sudo apt-get install -y apache2 libapache2-mod-wsgi
sudo ln -snf $CONFIG_DIR/sandcastle_apache2_ports.conf \
  /etc/apache2/ports.conf
sudo ln -snf $CONFIG_DIR/sandcastle_apache2_site \
  /etc/apache2/sites-available/sandcastle
sudo ln -snf $CONFIG_DIR/sandcastle_apache2_envvars \
  /etc/apache2/envvars
sudo a2dissite default
sudo a2ensite sandcastle
sudo service apache2 restart

echo "To finish setting up arc, copy sandcastle_dot_arcrc from Dropbox to"
echo "/home/sandcastle/.arcrc and chmod to 600"

# TODO(alpert): better sandcastle logging setup
