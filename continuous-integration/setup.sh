#!/bin/sh

# This sets up our continuous integration tools on EC2 Ubuntu11 AMI.
# Currently, only the continous deploy script is set up.
# TODO(david): Move Jenkins to this machine.
#
# Idempotent.
#
# This can be run like
#
# $ cat setup.sh | ssh <hostname of EC2 machine> sh

# Bail on any errors
set -e

sudo apt-get update

echo "Installing developer tools"
sudo apt-get install -y python-pip
sudo apt-get install -y git mercurial subversion
sudo apt-get install -y unzip
sudo apt-get install -y ruby rubygems
sudo REALLY_GEM_UPDATE_SYSTEM=1 gem update --system

echo "Syncing aws-config codebase"
git clone git://github.com/Khan/aws-config || ( cd aws-config && git pull )

echo "Copying dotfiles"
for i in aws-config/continuous-integration/dot_*; do
    cp "$i" ".`basename $i | sed 's/dot_//'`";
done

# TODO(benkomalo): would be nice to always get the latest version here
if [ ! -d "/usr/local/google_appengine" ]; then
    echo "Installing appengine"
    ( cd /tmp
      rm -rf google_appengine_1.7.0.zip google_appengine
      wget http://googleappengine.googlecode.com/files/google_appengine_1.7.0.zip
      unzip -o google_appengine_1.7.0.zip
      rm google_appengine_1.7.0.zip
      sudo mv -T google_appengine /usr/local/google_appengine
    )
fi

if [ ! -e "$HOME/kiln_extensions/kilnauth.py" ]; then
    echo "Downloading kilnauth"
    curl https://khanacademy.kilnhg.com/Tools/Downloads/Extensions > /tmp/extensions.zip && unzip /tmp/extensions.zip kiln_extensions/kilnauth.py
fi

echo "Installing node and npm"
sudo apt-get install -y nodejs
curl http://npmjs.org/install.sh | sudo sh

echo "Installing dependencies for exercises packing"
# ruby developer packages
sudo apt-get install -y ruby1.8-dev ruby1.8 ri1.8 rdoc1.8 irb1.8
sudo apt-get install -y libreadline-ruby1.8 libruby1.8 libopenssl-ruby
# nokogiri requirements (gem install does not suffice on Ubuntu)
# See http://nokogiri.org/tutorials/installing_nokogiri.html
sudo apt-get install -y libxslt-dev libxml2-dev
sudo gem install nokogiri
sudo gem install json uglifier therubyracer

echo "Setting up gae-continuous-deploy"
git clone --recursive git://github.com/Khan/gae-continuous-deploy || \
  ( cd gae-continuous-deploy && git pull )
sudo apt-get install -y build-essential gcc python-dev
# We don't actually create a virtualenv for the user, so this installs
# it into the system Python's dist-package directory (which requires sudo)
sudo pip install -r gae-continuous-deploy/requirements.txt
echo "TODO: Install secrets.py and secrets_dev.py to ~/gae-continuous-deploy/"
echo "TODO: hg clone https://khanacademy.kilnhg.com/Code/Website/Group/stable"
echo "      (only need credentials once; Kiln auth cookie will be saved)"
echo "TODO: Then run python deploy.py by hand."
