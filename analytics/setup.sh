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

echo "Installing python-pip"
sudo apt-get install -y python-pip

echo "Installing git/mercurial"
sudo apt-get install -y git mercurial

echo "Syncing analytics codebase"
git clone http://github.com/Khan/aws-config || ( cd aws-config && git pull )
git clone http://github.com/Khan/analytics || ( cd analytics && git pull )

echo "Installing unzip"
sudo apt-get install -y unzip

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

# TODO(benkomalo): this needs to be run manually

# To be able to send mail (c.f. http://flurdy.com/docs/postfix/ and
#  http://www.uponmyshoulder.com/blog/2010/set-up-a-mail-server-on-amazon-ec2/
# ) run:
# $ sudo vi /etc/postfix/main.cf -- change (second) myorigin to
#         $mydomain, change myhostname to ka-high-mem.khanacademy.org
#         # This is the setting to only send mail, not receive any
# $ sudo service postfix restart
