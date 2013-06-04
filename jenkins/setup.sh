#!/bin/sh

# This sets up our Jenkins on an EC2 Ubuntu12 AMI.
#
# Idempotent.
#
# This can be run like
#
# $ cat setup.sh | ssh <hostname of EC2 machine> sh

# Bail on any errors
set -e

CONFIG_DIR="$HOME"/aws-config/jenkins
JENKINS_HOME=/var/lib/jenkins

# Some builds need secrets.py from the webapp project. We create a place to
# store the secrets.py.cast5 decryption password, and to store secrets.py so
# it can be added to PYTHONPATH.
# TODO(chris): store the password securely.
SECRETS_DIR="${JENKINS_HOME}"/secrets_py
SECRETS_PW="${SECRETS_DIR}"/secrets.py.cast5.password

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
    sudo apt-get install -y curl
    sudo apt-get install -y python-pip
    sudo apt-get install -y python-dev  # for numpy
    sudo apt-get install -y git mercurial subversion
    sudo apt-get install -y unzip
    sudo apt-get install -y ruby rubygems
    sudo REALLY_GEM_UPDATE_SYSTEM=1 gem update --system

    # This is needed so installing postfix doesn't prompt.  See
    # http://www.ossramblings.com/preseed_your_apt_get_for_unattended_installs
    # If it prompts anyway, type in the stuff from postfix.preseed manually.
    sudo apt-get install -y debconf-utils
    sudo debconf-set-selections "${CONFIG_DIR}"/postfix.preseed
    sudo apt-get install -y postfix
    echo "(Finishing up postfix config)"
    sudo sed -i -e 's/myorigin = .*/myorigin = khanacademy.org/' \
                -e 's/myhostname = .*/myhostname = jenkins.khanacademy.org/' \
                -e 's/inet_interfaces = all/inet_interfaces = loopback-only/' \
                /etc/postfix/main.cf
    sudo service postfix restart
}

install_build_deps() {
    echo "Installing build dependencies"

    # secrets.py is needed by the translations build and deployment
    mkdir -p "${SECRETS_DIR}"
    if [ ! -e "$SECRETS_PW" ]; then
        echo "Put the password to decrypt secrets.py on the first line of this file. See https://www.dropbox.com/home/Khan%20Academy%20All%20Staff/Secrets" >"${SECRETS_PW}"
    fi

    if [ ! -e "$HOME"/kiln_extensions/kilnauth.py ]; then
        echo "Installing the kilnauth Mercurial plugin"
        curl https://khanacademy.kilnhg.com/Tools/Downloads/Extensions > /tmp/extensions.zip && unzip /tmp/extensions.zip kiln_extensions/kilnauth.py
    fi

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
    sudo gem install nokogiri
    sudo gem install json uglifier therubyracer
}

install_google_app_engine() {
    # TODO(benkomalo): Would be nice to always get the latest version here.
    # See http://stackoverflow.com/questions/15487357/how-to-get-the-current-dev-appserver-version/15489674
    # See https://developers.google.com/appengine/downloads to find the most
    # recent version.  You should be able to simply bump $LATESTVERSION and the
    # rest will work.
    LATESTVERSION="1.8.0"
    GAEFILENAME="google_appengine_${LATESTVERSION}.zip"
    GAEDOWNLOADLINK="http://googleappengine.googlecode.com/files/${GAEFILENAME}"
    INSTALLGAE="false"
    INSTALLDIR="/usr/local/google_appengine"

    if [ ! -d "$INSTALLDIR" ]; then
        INSTALLGAE="true"
    fi

    if [ "$INSTALLGAE" != "true" ]; then
        INSTALLEDVERSION=`cat "$INSTALLDIR"/VERSION | grep release | cut -d: -f 2 | cut -d\" -f 2`
        if [ "$INSTALLEDVERSION" != "$LATESTVERSION" ]; then
            INSTALLGAE="true"
        fi
    fi

    if [ "$INSTALLGAE" = "true" ]; then
        echo "Installing Google AppEngine"
        ( cd /tmp
          rm -rf "$GAEFILENAME" google_appengine
          wget "$GAEDOWNLOADLINK"
          unzip -o "$GAEFILENAME"
          rm "$GAEFILENAME"
          sudo rm -rf "$INSTALLDIR"
          sudo mv -T google_appengine "$INSTALLDIR"
        )
    fi
}

install_jenkins() {
    echo "Installing Jenkins"

    # Set up a compatible Java.
    sudo apt-get install -y openjdk-6-jre openjdk-6-jdk
    sudo ln -snf /usr/lib/jvm/java-6-openjdk /usr/lib/jvm/default-java

    jenkins_cli_jar="${HOME}"/bin/jenkins-cli.jar
    jenkins_plugin_url=http://updates.jenkins-ci.org/download/plugins

    # Instructions for installing on Ubuntu are from
    # https://wiki.jenkins-ci.org/display/JENKINS/Installing+Jenkins+on+Ubuntu
    sudo apt-key add "${CONFIG_DIR}"/jenkins-ci.org.key
    sudo sh -c 'echo deb http://pkg.jenkins-ci.org/debian binary/ >/etc/apt/sources.list.d/jenkins.list'
    sudo apt-get update

    sudo apt-get install -y jenkins     # http://jenkins-ci.org

    # Authorize Jenkins to access kiln repos.
    # TODO(chris): right now this uses the personal auth of whatever
    # gets entered at the auth prompt. There should be a read-only
    # account for accessing the kiln repos.
    sudo -u jenkins sh -c "echo \"[extensions]
kilnauth = ${HOME}/kiln_extensions/kilnauth.py\" > \"${JENKINS_HOME}\"/.hgrc"

    # Ensure plugins directory exists.
    sudo -u jenkins mkdir -p "${JENKINS_HOME}"/plugins

    # Install plugins (versions initially chosen for Jenkins v1.512).
    for plugin in \
        "cobertura/1.8/cobertura.hpi" \
        "disk-usage/0.19/disk-usage.hpi" \
        "email-ext/2.28/email-ext.hpi" \
        "envinject/1.85/envinject.hpi" \
        "git-client/1.0.5/git-client.hpi" \
        "git/1.3.0/git.hpi" \
        "hipchat/0.1.4/hipchat.hpi" \
        "htmlpublisher/1.2/htmlpublisher.hpi" \
        "mercurial/1.45/mercurial.hpi" \
        "openid/1.6/openid.hpi" \
        "simple-theme-plugin/0.3/simple-theme-plugin.hpi" \
        ;
    do
        plugin_url="${jenkins_plugin_url}/${plugin}"
        plugin_file=`basename "${plugin}"`
        plugin_dir=`echo "${plugin_file}" | sed 's/\.hpi//'`
        sudo -u jenkins sh -c "cd \"${JENKINS_HOME}\"/plugins && rm -rf \"${plugin_file}\" \"${plugin_dir}\" && wget \"${plugin_url}\""
    done

    # Start the daemon
    sudo update-rc.d jenkins defaults
    sudo service jenkins restart || sudo service jenkins start
}

install_nginx() {
    echo "Installing nginx"
    sudo apt-get install -y nginx
    sudo rm -f /etc/nginx/sites-enabled/default
    sudo ln -sfnv "${CONFIG_DIR}"/nginx_site_jenkins /etc/nginx/sites-available/jenkins
    sudo ln -sfnv /etc/nginx/sites-available/jenkins /etc/nginx/sites-enabled/jenkins
    sudo service nginx restart
}

update_aws_config_env
install_basic_packages
install_build_deps
install_google_app_engine
install_jenkins
install_nginx

echo
echo "TODO: Set the password for secrets.py in ${SECRETS_PW}"
echo "TODO: generate an SSH key pair for Jenkins, register the public key with "
echo "      Kiln for SSH access, and copy the key pair to ${JENKINS_HOME}/.ssh/"
echo "TODO: copy files from jenkins_home/ to ${JENKINS_HOME}"
