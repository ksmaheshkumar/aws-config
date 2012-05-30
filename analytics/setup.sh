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


# TODO(benkomalo): the mongo on the main Ubuntu repositories may be slightly
# behind the latest stable version suggested by the Mongo dev team
# TODO(benkomalo): should this run as root?
echo "Setting up mongodb"
sudo apt-get install -y mongodb
sh aws-config/analytics/mongo_cntrl restart

echo "Prepping EBS mount points"
sudo apt-get install -y ec2-api-tools
sudo mkdir -p /ebs/kalogs  # App Engine logs
sudo mkdir -p /ebs/kadata  # Mongo db 1
sudo mkdir -p /ebs/kadata2 # Mongo db 2
ln -sf /ebs/kalogs
ln -sf /ebs/kadata
ln -sf /ebs/kadata2

# TODO(benkomalo): automate the actual mounting somehow using
# ec2-attach-volume and/or ec2-describe-volumes
cat <<EOF

NOTE: you need to add something like the following
to your /etc/fstab. Unfortunately, when AWS attaches EBS volumes to EC2,
the device name isn't consistent, so /dev/sdg may be /dev/xvdg or something
else that's cryptic. Check the AWS console for what the device name should
be.

/dev/xvdg    /ebs/kalogs         auto	defaults,comment=cloudconfig	0	2
/dev/xvdh    /ebs/kadata         auto	defaults,comment=cloudconfig	0	2
/dev/xvdi    /ebs/kadata2        auto	defaults,comment=cloudconfig	0	2
EOF

# TODO(benkomalo): not sure how to automate this next part quite yet
cat <<EOF

NOTE: Don't forget you need to manually run:
$ cd analytics/src/oauth_util/
$ ./get_access_token.py
$ chmod 600 access_token.py

To have scripts authenticated. This is an interactive process which
requires a browser and developer credentials against our GAE app.
It may be that you may have to do this on a local machine and scp it
over. :(
EOF