#!/bin/sh

# This sets up our continuous integration tools on EC2 Ubuntu11 AMI.
# Currently, only the continous deploy script and its web server is set up.
# TODO(david): Move Jenkins to this machine.
#
# Idempotent.
#
# This can be run like
#
# $ cat setup.sh | ssh <hostname of EC2 machine> sh

# Bail on any errors
set -e

CONFIG_DIR=$HOME/aws-config/continuous-integration

cd $HOME

sudo apt-get update

echo "Installing developer tools"
sudo apt-get install -y curl
sudo apt-get install -y python-pip
sudo apt-get install -y git mercurial subversion
sudo apt-get install -y unzip
sudo apt-get install -y ruby rubygems
sudo REALLY_GEM_UPDATE_SYSTEM=1 gem update --system

echo "Syncing aws-config codebase"
if [ ! -d aws-config ]; then
    git clone git://github.com/Khan/aws-config
fi

( cd aws-config && git pull )

echo "Copying dotfiles"
for i in aws-config/continuous-integration/dot_*; do
    cp "$i" ".`basename $i | sed 's/dot_//'`";
done

echo "Copying usr to /usr"
sudo cp -savf "$HOME/aws-config/continuous-integration/usr/" /

# TODO(benkomalo): Would be nice to always get the latest version here.
# See http://stackoverflow.com/questions/15487357/how-to-get-the-current-dev-appserver-version/15489674
# See https://developers.google.com/appengine/downloads to find the most recent
# version.  You should be able to simply bump $LATESTVERSION and the rest will work.
LATESTVERSION="1.7.5"
GAEFILENAME="google_appengine_$LATESTVERSION.zip"
GAEDOWNLOADLINK="http://googleappengine.googlecode.com/files/$GAEFILENAME"
INSTALLGAE="false"
INSTALLDIR="/usr/local/google_appengine"

if [ ! -d $INSTALLDIR ]; then
    INSTALLGAE="true"
fi

if [ $INSTALLGAE != "true" ]; then
    INSTALLEDVERSION=`cat $INSTALLDIR/VERSION | grep release | cut -d: -f 2 | cut -d\" -f 2`
    if [ $INSTALLEDVERSION != $LATESTVERSION ]; then
        INSTALLGAE="true"
    fi
fi

if [ $INSTALLGAE = "true" ]; then
    echo "Installing appengine"
    ( cd /tmp
      rm -rf $GAEFILENAME google_appengine
      rm -rf $INSTALLDIR
      mkdir $INSTALLDIR
      wget $GAEDOWNLOADLINK
      unzip -o $GAEFILENAME
      rm $GAEFILENAME
      sudo mv -T google_appengine $INSTALLDIR
    )
fi

if [ ! -e "$HOME/kiln_extensions/kilnauth.py" ]; then
    echo "Downloading kilnauth"
    curl https://khanacademy.kilnhg.com/Tools/Downloads/Extensions > /tmp/extensions.zip && unzip /tmp/extensions.zip kiln_extensions/kilnauth.py
fi

echo "Installing node and npm"
# see https://github.com/joyent/node/wiki/Installing-Node.js-via-package-manager
sudo apt-get install python-software-properties python g++ make
sudo add-apt-repository ppa:chris-lea/node.js
sudo apt-get update
sudo apt-get install -y nodejs
# If npm is not installed, log in to the CI machine and run this command:
# TODO(mattfaus): Automate this (ran into problems with /dev/tty)
# wget -q -O- https://npmjs.org/install.sh | sudo sh
sudo npm update

echo "Installing dependencies for exercises packing"
# ruby developer packages
sudo apt-get install -y ruby1.8-dev ruby1.8 ri1.8 rdoc1.8 irb1.8
sudo apt-get install -y libreadline-ruby1.8 libruby1.8 libopenssl-ruby
# nokogiri requirements (gem install does not suffice on Ubuntu)
# See http://nokogiri.org/tutorials/installing_nokogiri.html
sudo apt-get install -y libxslt-dev libxml2-dev
sudo gem install nokogiri
sudo gem install json uglifier therubyracer

echo "Installing redis"
sudo apt-get install -y redis-server

echo "Installing nginx"
sudo apt-get install -y nginx
sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -sfnv $CONFIG_DIR/etc/nginx/sites-available/mr_deploy \
  /etc/nginx/sites-available/mr_deploy
sudo ln -sfnv /etc/nginx/sites-available/mr_deploy \
  /etc/nginx/sites-enabled/mr_deploy
sudo service nginx restart

echo "Setting up gae-continuous-deploy"
git clone --recursive git://github.com/Khan/gae-continuous-deploy || \
  ( cd gae-continuous-deploy && git pull )
ln -sfnv "$HOME/gae-continuous-deploy/log" "$HOME/deploy-logs"
sudo ln -sfnv $CONFIG_DIR/etc/logrotate.d/gae-continuous-deploy /etc/logrotate.d
# This is needed for mercurial in requirements.txt
sudo apt-get install -y build-essential gcc python-dev
# This is needed for gevent in requirements.txt
sudo apt-get install -y libevent-dev python-all-dev
# We don't actually create a virtualenv for the user, so this installs
# it into the system Python's dist-package directory (which requires sudo)
sudo pip install -r gae-continuous-deploy/requirements.txt

echo "Installing gae-continuous-deploy as a daemon"
sudo ln -sfnv $CONFIG_DIR/etc/init/mr-deploy-daemon.conf /etc/init

# Ubuntu only provides a phantomjs package for 12.04 and newer. The prebuilt
# Linux binary from phantomjs.org only works with Ubuntu 11.10 and earlier,
# so the most compatible route is to compile from source. Unfortunately, it's
# got some large dependencies (namely WebKit) so it takes a while to compile.
#
# See http://phantomjs.org/build.html
#
# Note: Point releases of PhantomJS should be tested before adoption because
# they often introduce API changes that might break rasterize.js in
# exercise-screens. The last tested verison of PhantomJS was (as of
# 2013-03-07), 1.6.2.
#
# TODO(cbhl): Consider swtiching to using the phantomjs package in 14.04. (The
# phantomjs package that ships with 12.04 is version 1.4, which depends on a
# running X server. Phantomjs became truely headless in 1.5.)
if [ ! -e "/usr/local/phantomjs" ]; then
  echo "Compiling phantomjs"
  sudo apt-get install -y chrpath libssl-dev libfontconfig1-dev
  git clone git://github.com/ariya/phantomjs || \
    ( cd phantomjs && git checkout 1.6 )
  phantomjs/build.sh --jobs 1
  echo "Installing phantomjs"
  phantomjs/deploy/package.sh
  sudo cp -r phantomjs/deploy/phantomjs-1.6.2-linux-x86_64-dynamic \
    /usr/local/phantomjs
  rm -rf phantomjs
fi

echo "Setting up exercise-screens"
sudo apt-get -y install imagemagick
git clone git://github.com/Khan/exercise-screens || \
  ( cd exercise-screens && git pull )
# We don't actually create a virtualenv for the user, so this installs
# it into the system Python's dist-package directory (which requires sudo)
sudo pip install -r exercise-screens/requirements.txt

echo "Installing exercise-screens as a daemon"
# Symlinks are not allowed for upstart jobs by design, so make a copy.
sudo cp -afv $CONFIG_DIR/etc/init/exercise-screens-daemon.conf /etc/init

echo "TODO: Install secrets.py and secrets_dev.py to ~/gae-continuous-deploy/"
echo "TODO: hg clone https://khanacademy.kilnhg.com/Code/Website/Group/stable"
echo "      (only need credentials once; Kiln auth cookie will be saved)"
echo "TODO: Then run make deploy by hand."
echo
echo "TODO: Create exercise-screens/secrets.py and define"
echo "      AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
echo "      that have S3 write permissions to the screenshot bucket."
echo "TODO: Then run sudo service exercise-screens-daemon start"
