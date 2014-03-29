#!/bin/sh

# This sets up packages needed on an EC2 machine for the reports machine
# This is based on the Ubuntu11 AMI that Amazon provides as one of
# the default EC2 AMI options. It is idempotent.
#
# This should be run in the home directory of the role account
# of the user that is to run the analytics report jobs
#
# Typically, this is run like this
#
# $ cat setup.sh | ssh <hostname of EC2 machine> sh

# First, you need to create the analytics role account on the machine:
# See ../create_role_account.sh for an automated way to do this.

# Second, make sure any EBS volumes are attached, mounted, 
# and ~/logs and ~/data are links to appropriate directories thereon. 

# TODO(benkomalo): remove duplication with this and setup.sh in analytics

# Bail on any errors
set -e

sudo apt-get update

echo "Installing developer tools"
sudo apt-get install -y ntp
sudo apt-get install -y python-pip
sudo apt-get install -y build-essential python-dev
sudo apt-get install -y git mercurial

echo "Syncing analytics codebase"
git clone http://github.com/Khan/aws-config || ( cd aws-config && git pull )
git clone http://github.com/Khan/analytics || ( cd analytics && git pull )

# We don't actually create a virtualenv for the user, so this installs
# it into the system Python's dist-package directory (which requires sudo)
sudo pip install -r analytics/requirements.txt

echo "Setting up mongodb"
# http://docs.mongodb.org/manual/tutorial/install-mongodb-on-ubuntu/
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv 7F0CEB10
echo 'deb http://downloads-distro.mongodb.org/repo/ubuntu-upstart dist 10gen' | sudo tee /etc/apt/sources.list.d/10gen.list
sudo apt-get update
sudo apt-get install mongodb-10gen

aws-config/reports/mongo_cntrl restart

# Install sleepy mongoose
sudo pip install bson
git clone https://github.com/kchodorow/sleepy.mongoose 2> /dev/null

# TODO(benkomalo) have to run this manually to start sleepymongoose
# automate this in a daemon
# nohup python httpd.py 2>&1 ~/logs/mongo/sleepymongoose.log &
