#!/bin/sh

# This sets up packages needed on an EC2 machine for analytics
# This is based on the Ubuntu11 AMI that Amazon provides as one of
# the default EC2 AMI options. It is idempotent.
#
# This should be run in the home directory of the role account
# of the user that is to run the analytics jobs.

# Typically, this is run like this
#
# $ cat setup.sh | ssh <hostname of EC2 machine> sh

# Bail on any errors
set -e

sudo apt-get update

echo "Installing developer tools"
sudo apt-get install -y python-pip
sudo apt-get install -y build-essential python-dev
sudo apt-get install -y git mercurial
sudo apt-get install -y unzip

echo "Syncing analytics codebase"
git clone http://github.com/Khan/aws-config || ( cd aws-config && git pull )
git clone http://github.com/Khan/analytics || ( cd analytics && git pull )

# We don't actually create a virtualenv for the user, so this installs
# it into the system Python's dist-package directory (which requires sudo)
sudo pip install -r analytics/requirements.txt

# TODO(benkomalo): would be nice to always get the latest version here
if [ ! -d "/usr/local/google_appengine" ]; then
    echo "Installing appengine"
    ( cd /tmp
      rm -rf google_appengine_1.6.6.zip google_appengine
      wget http://googleappengine.googlecode.com/files/google_appengine_1.6.6.zip
      unzip -o google_appengine_1.6.6.zip
      rm google_appengine_1.6.6.zip
      sudo mv -T google_appengine /usr/local/google_appengine
    )
fi

echo "Installing crontab"
crontab aws-config/analytics/crontab

echo "Copying dotfiles"
for i in aws-config/analytics/dot_*; do
    cp "$i" ".`basename $i | sed 's/dot_//'`";
done

echo "Installing postfix (along with pre-requisites)"
# This is needed so installing postfix doesn't prompt.  See
# http://www.ossramblings.com/preseed_your_apt_get_for_unattended_installs
sudo apt-get install -y debconf-utils
sudo debconf-set-selections aws-config/analytics/postfix.preseed
sudo apt-get install -y postfix

echo "Setting up postfix config"
sudo sed -i -e 's/myorigin = .*/myorigin = khanacademy.org/' \
            -e 's/myhostname = .*/myhostname = analytics.khanacademy.org/' \
            -e 's/inet_interfaces = all/inet_interfaces = loopback-only/' \
            /etc/postfix/main.cf
sudo service postfix restart

echo "Setting up log directories"
mkdir -p log/mongo

echo "Setting up mongodb"
sudo apt-get install -y mongodb
sh aws-config/analytics/mongo_cntrl restart

# TODO(benkomalo): not sure how to automate this next part quite yet
echo <<EOF

NOTE: Don't forget you need to manually run:
$ cd analytics/src/oauth_util/
$ ./get_access_token.py
$ chmod 600 access_token.py

To have scripts authenticated. This is an interactive process which
requires a browser and developer credentials against our GAE app.
It may be that you may have to do this on a local machine and scp it
over. :(
EOF
