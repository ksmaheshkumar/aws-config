#!/bin/sh

# This sets up packages needed on an EC2 machine for analytics
# This is based on the Ubuntu11 AMI that Amazon provides as one of
# the default EC2 AMI options. It is idempotent.
#
# This should be run in the home directory of the role account
# of the user that is to run the analytics jobs.
#
# NOTE: This script, along with some of the data files in this
# directory (notably etc/fstab), assume that a 'data' disks have been
# attached to this ec2 instance as follows:
#    /dev/xvdf1  (modeling)
#    /dev/xvdg1  (kalogs)
#    /dev/xvdh1  (kadata)
#    /dev/xvdi1  (kadata2)
# TODO(benkomalo): automate the attaching using ec2-attach-volume
# and/or ec2-describe-volumes
#
# Typically, this is run like this
#
# $ cat setup.sh | ssh <hostname of EC2 machine> sh

# Bail on any errors
set -e

sudo apt-get update

install_basic_packages() {
    echo "Installing developer tools"
    sudo apt-get install -y ntp
    sudo apt-get install -y python-pip
    sudo apt-get install -y build-essential python-dev
    sudo apt-get install -y unzip
    sudo apt-get install -y libatlas-base-dev gfortran  # needed for scipy
    sudo apt-get install -y libxml2-dev libxslt1-dev  # needed for lxml.py
    sudo apt-get install -y r-base

    # This is needed so installing postfix doesn't prompt.  See
    # http://www.ossramblings.com/preseed_your_apt_get_for_unattended_installs
    sudo apt-get install -y debconf-utils
    sudo debconf-set-selections aws-config/analytics/postfix.preseed
    sudo apt-get install -y postfix
    echo "(Finishing up postfix config)"
    sudo sed -i -e 's/myorigin = .*/myorigin = khanacademy.org/' \
                -e 's/myhostname = .*/myhostname = analytics.khanacademy.org/' \
                -e 's/inet_interfaces = all/inet_interfaces = loopback-only/' \
                /etc/postfix/main.cf
    sudo service postfix restart
}

install_repositories() {
    echo "Syncing analytics codebase"
    sudo apt-get install -y git
    git clone http://github.com/Khan/aws-config || ( cd aws-config && git pull )
    git clone http://github.com/Khan/analytics || ( cd analytics && git pull )

    # We don't actually create a virtualenv for the user, so this installs
    # it into the system Python's dist-package directory (which requires sudo)
    sudo pip install -r analytics/requirements.txt
}

install_appengine() {
    # TODO(benkomalo): would be nice to always get the latest version here
    zipfile="google_appengine_1.8.1.zip"
    if [ ! -d "/usr/local/google_appengine" ]; then
        echo "Installing appengine"
        ( cd /tmp
          rm -rf "$zipfile" google_appengine
          wget http://googleappengine.googlecode.com/files/"$zipfile"
          unzip -o "$zipfile"
          rm "$zipfile"
          sudo mv -T google_appengine /usr/local/google_appengine
        )
    fi
}

install_amazon() {
    echo "Installing Amazon Elastic MapReduce"
    ( cd /tmp
      rm -rf elastic-mapreduce-ruby.zip emr
      wget http://elasticmapreduce.s3.amazonaws.com/elastic-mapreduce-ruby.zip
      mkdir emr
      unzip -o elastic-mapreduce-ruby.zip -d emr
      rm elastic-mapreduce-ruby.zip
      mv -T emr $HOME/emr
    )
}

install_root_config_files() {
    # (Some of this work is done in install_webserver as well.)

    # Make sure that we've added the info we need to the fstab.
    # ('tee -a' is the way to do '>>' that works with sudo.)
    grep -xqf "$HOME"/aws-config/analytics/etc/fstab.extra /etc/fstab || \
        cat "$HOME"/aws-config/analytics/etc/fstab.extra \
        | sudo tee -a /etc/fstab >/dev/null

    echo "Prepping EBS mount points"
    awk '{print $2}' "$HOME"/aws-config/analytics/etc/fstab.extra \
        | while read dir; do sudo mkdir -p "$dir"; done

    # Make sure all the disks in the fstab are mounted.
    sudo mount -a
}

install_user_config_files() {
    echo "Copying dotfiles"
    for i in aws-config/analytics/dot_*; do
        cp "$i" ".`basename $i | sed 's/dot_//'`";
    done

    echo "Prepping EBS-volume symlinks"
    awk '{print $2}' "$HOME"/aws-config/analytics/etc/fstab.extra \
        | while read dir; do ln -snf "$dir"; done
}

install_database() {
    # TODO(benkomalo): the mongo on the main Ubuntu repositories may be slightly
    # behind the latest stable version suggested by the Mongo dev team
    echo "Setting up mongodb"
    sudo apt-get install -y mongodb
    sudo aws-config/analytics/mongo_cntrl restart
}

install_webserver() {
    echo "Installing lighttpd proxy"
    sudo apt-get install -y lighttpd
    sudo mkdir $HOME/log/lighttpd
    sudo chown -R www-data:www-data $HOME/log/lighttpd
    sudo ln -snf $HOME/aws-config/analytics/etc/lighttpd/lighttpd.conf /etc/lighttpd/
    sudo service lighttpd restart
}

install_web_services() {
    echo "Installing dashboard webapp as a daemon"
    sudo update-rc.d -f dashboards-daemon remove
    sudo ln -snf $HOME/aws-config/analytics/etc/init.d/dashboards-daemon /etc/init.d
    sudo update-rc.d dashboards-daemon defaults
    sudo service dashboards-daemon restart
}


cd "$HOME"
install_basic_packages
install_repositories
install_root_config_files
install_user_config_files
install_appengine
install_amazon
install_database
install_webserver
install_web_services


# TODO(benkomalo): not sure how to automate this next part quite yet
cat <<EOF
--------------
NOTE: Don't forget you need to manually run:
$ cd analytics/src/oauth_util/
$ ./get_access_token.py
$ chmod 600 access_token.py

To have scripts authenticated. This is an interactive process which
requires a browser and developer credentials against our GAE app.
It may be that you may have to do this on a local machine and scp it
over. :(

--------------
NOTE: You'll also need a service account's client_secrets.json and
private key to authenticate the dashboards webapp against Google
Analytics' API. This is an interactive process which requires a
browser and developer credentials against our Google Cloud Project.
You'll probably have to do this on a local machine and SCP it over :(

To install ga_client_secrets.json:

Visit the page for the KA app's credentials
https://cloud.google.com/console/project/apps~khan-academy/apiui/credential
and click "Download JSON" under "Service Account", then:

$ mv <DOWNLOADED_FILE> ga_client_secrets.json
$ chmod 600 ga_client_secrets.json
$ scp ga_client_secrets.json analytics:~/analytics/webapps/dashboards/ga_client_secrets.json

To install ga_client_privatekey.p12:

First download the private key file from
https://www.dropbox.com/home/Khan%20Academy%20All%20Staff/Secrets/b297cf4c-privatekey.p12

$ mv <DOWNLOADED_FILE> ga_client_privatekey.p12
$ chmod 600 ga_client_privatekey.p12
$ scp ga_client_privatekey.p12 analytics:~/analytics/webapps/dashboards/ga_client_privatekey.p12

--------------
NOTE: You'll also need a credentials.json with AWS keys for the Elastic
MapReduce Ruby client in ~/emr. See
http://elasticmapreduce.s3.amazonaws.com/elastic-mapreduce-ruby.zip

# TODO(benkomalo): there are some scripts that rely on s3cmd to upload data
# to S3. This requires a $HOME/.s3cfg file to be made with credentials

--------------
NOTE: You will need to copy the value of sleep_secret from secrets.py
and put it in $HOME/sleep_secret.  This is needed for load_emr_daily.sh

--------------
NOTE: You will need to copy the value of hostedgraphite_api_key from
secrets.py and put it in $HOME/hostedgraphite_secret.  This is needed
for src/gae_dashboard/dashboard_report.py.
EOF

# Finally, we can start the crontab!
echo "Installing crontab"
crontab "$HOME/aws-config/analytics/crontab"

