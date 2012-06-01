#!/bin/sh

# This sets up packages needed on an EC2 machine for youtube-export and
# sandcastle.  This is based on the Ubuntu11 AMI that Amazon provides as one of
# the default EC2 AMI options. It is idempotent.
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
#sudo apt-get install -y build-essential python-dev
sudo apt-get install -y git mercurial

echo "Syncing sandcastle and youtube-export codebase"
git clone http://github.com/Khan/aws-config || ( cd aws-config && git pull )
git clone http://github.com/Khan/sandcastle || ( cd sandcastle && git pull )
hg clone https://khanacademy.kilnhg.com/Code/Website/tools/youtube-export || \
  ( cd youtube-export && hg pull -u )

# We don't actually create a virtualenv for the user, so this installs
# it into the system Python's dist-package directory (which requires sudo)
sudo pip install -r sandcastle/requirements.txt
sudo pip install -r youtube-export/requirements.txt

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

echo "Setting up sandcastle"
mkdir -p sandcastle/apache
ln -snf $CONFIG_DIR/sandcastle_apache_django.wsgi sandcastle/apache/django.wsgi
ln -snf $CONFIG_DIR/sandcastle_local_settings.py sandcastle/local_settings.py
sudo chown -R www-data:www-data sandcastle/media/castles/

sudo apt-get install -y apache2 libapache2-mod-wsgi
sudo ln -snf $CONFIG_DIR/sandcastle_apache2_ports.conf \
  /etc/apache2/ports.conf
sudo ln -snf $CONFIG_DIR/sandcastle_apache2_site \
  /etc/apache2/sites-available/sandcastle
sudo a2dissite default
sudo a2ensite sandcastle
sudo service apache2 restart

sudo apt-get install -y nginx
sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -snf $CONFIG_DIR/sandcastle_nginx_site \
  /etc/nginx/sites-available/sandcastle
sudo ln -snf /etc/nginx/sites-available/sandcastle \
  /etc/nginx/sites-enabled/sandcastle
sudo service nginx restart

# TODO(alpert): mount EBS and set up media/castles appropriately
# TODO(alpert): set up and test youtube-export cron jobs
