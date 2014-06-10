#!/bin/sh

# This sets up a Jenkins slave machine on an EC2 Ubuntu12 AMI.
#
# Most likely, this will only be used to create a customized AMI
# (based on the standard ubuntu12 AMI) that the jenkins ec2 plugin
# will use when creating slaves on the fly for us.
#
# This can be run like
#
# $ cat setup.sh | ssh ubuntu@<hostname of EC2 machine> sh

# Bail on any errors
set -e

CONFIG_DIR="$HOME"/aws-config/jenkins
JENKINS_HOME="$HOME"

cd "$HOME"

update_aws_config_env() {
    echo "Update aws-config codebase and installation environment"
    # Make sure the system is up-to-date.
    sudo apt-get update
    sudo apt-get install -y git

    if [ ! -d aws-config ]; then
        git clone git://github.com/Khan/aws-config
    fi
    ( cd aws-config && git pull )
}

install_basic_packages() {
    echo "Installing basic packages"
    sudo apt-get install -y ntp
    sudo apt-get install -y curl
    sudo apt-get install -y ncurses-dev
    sudo apt-get install -y python-pip
    sudo apt-get install -y python-dev  # for numpy
    sudo apt-get install -y git mercurial subversion
    sudo apt-get install -y unzip
    sudo apt-get install -y ruby rubygems
    sudo REALLY_GEM_UPDATE_SYSTEM=1 gem update --system

    # Some KA tests write to /tmp and don't clean up after themselves,
    # on purpose (see kake/server_client.py:rebuild_if_needed().  We
    # install tmpreaper to clean up those files "eventually".
    # This avoids promppting at install time.
    sudo apt-get install -y debconf-utils
    echo "tmpreaper tmpreaper/readsecurity note" | sudo debconf-set-selections
    echo "tmpreaper tmpreaper/readsecurity_upgrading note" | sudo debconf-set-selections
    sudo apt-get install -y tmpreaper
    # We need to comment out a line before tmpreaper will actually run.
    sudo perl -pli -e s/^SHOWWARNING/#SHOWWARNING/ /etc/tmpreaper.conf
}

install_user_env() {
    sudo cp -av "$CONFIG_DIR/.gitconfig" "$JENKINS_HOME/.gitconfig"
    sudo cp -av "$CONFIG_DIR/.ssh" "$JENKINS_HOME/"
    sudo chown -R ubuntu.nogroup "$JENKINS_HOME/.gitconfig"
    sudo chown -R ubuntu.nogroup "$JENKINS_HOME/.ssh"
    sudo chmod 600 "$JENKINS_HOME/.ssh/config"
}

install_phantomjs() {
    if ! which phantomjs >/dev/null; then
        (
            cd /usr/local/share
            case `uname -m` in
                i?86) mach=i686;;
                *) mach=x86_64;;
            esac
            sudo rm -rf phantomjs
            wget "https://phantomjs.googlecode.com/files/phantomjs-1.9.2-linux-${mach}.tar.bz2" -O- | sudo tar xfj -

            sudo ln -snf /usr/local/share/phantomjs-1.9.2-linux-${mach}/bin/phantomjs /usr/local/bin/phantomjs
        )
        which phantomjs >/dev/null
    fi
}

install_build_deps() {
    echo "Installing build dependencies"

    sudo apt-get install -y g++ make

    # Python deps
    sudo apt-get install -y python-software-properties python
    sudo pip install virtualenv

    # Node deps
    # see https://github.com/joyent/node/wiki/Installing-Node.js-via-package-manager
    sudo add-apt-repository -y ppa:chris-lea/node.js
    sudo apt-get update
    sudo apt-get install -y nodejs
    # If npm is not installed, log in to the jenkins machine and run this command:
    # TODO(mattfaus): Automate this (ran into problems with /dev/tty)
    # wget -q -O- https://npmjs.org/install.sh | sudo sh
    sudo npm update

    # Ruby deps
    sudo apt-get install -y ruby1.8-dev ruby1.8 ri1.8 rdoc1.8 irb1.8
    sudo apt-get install -y libreadline-ruby1.8 libruby1.8 libopenssl-ruby
    # nokogiri requirements (gem install does not suffice on Ubuntu)
    # See http://nokogiri.org/tutorials/installing_nokogiri.html
    sudo apt-get install -y libxslt-dev libxml2-dev
    # NOTE: version 2.x of uglifier has unexpected behavior that causes
    # khan-exercises/build/pack.rb to fail.
    sudo gem install --conservative nokogiri:1.5.7 json:1.7.7 uglifier:1.3.0 therubyracer:0.11.4

    # jstest deps
    install_phantomjs
}

install_jenkins_slave() {
    echo "Installing Jenkins Slave"

    # Set up a compatible Java.
    sudo apt-get install -y openjdk-6-jre openjdk-6-jdk
    sudo ln -snf /usr/lib/jvm/java-6-openjdk /usr/lib/jvm/default-java
}

update_aws_config_env
install_user_env
install_basic_packages
install_build_deps
install_jenkins_slave

echo "TODO: copy jenkins:/var/lib/jenkins/.ssh/id_rsa.ReadWriteKiln* to .ssh"
