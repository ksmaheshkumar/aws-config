#!/bin/sh

# This sets up our Jenkins on an EC2 Ubuntu12 AMI.
#
# Idempotent.  Run this as the ubuntu user (though most of the work
# will be done as the jenkins user).
#
# NOTE: This script assumes that a 'data' disk has been attached to
# this ec2 instance as sdb (aka xvdb) and mounted at /mnt!  I think
# aws can do this for you by default when you set up the instance.
#
# This can be run like
#
# $ cat setup.sh | ssh ubuntu@<hostname of EC2 machine> sh

# Bail on any errors
set -e

CONFIG_DIR="$HOME"/aws-config/jenkins
# Installing jenkins creates a jenkins user whose $HOME is this directory.
JENKINS_HOME=/var/lib/jenkins

# Some builds need secrets.py from the webapp project. We create a place to
# store the secrets.py.cast5 decryption password, and to store secrets.py so
# it can be added to PYTHONPATH.
# TODO(chris): store the password securely.
SECRETS_DIR="${JENKINS_HOME}"/secrets_py
SECRETS_PW="${SECRETS_DIR}"/secrets.py.cast5.password
PROD_SECRETS_PW="${JENKINS_HOME}/prod-deploy.pw"

cd "$HOME"

update_aws_config_env() {
    echo "Update aws-config codebase and installation environment"
    # To get the most recent git, later.
    if ! ls /etc/apt/sources.list.d/ 2>&1 | grep -q git-core-ppa; then
        sudo add-apt-repository -y ppa:git-core/ppa
        updated_apt_repo=yes
    fi

    # Make sure the system is up-to-date.
    sudo apt-get update
    sudo apt-get install -y git

    if [ ! -d aws-config ]; then
        git clone git://github.com/Khan/aws-config
    fi
    ( cd aws-config && git pull && git submodule update --init --recursive )
}

install_global_env() {
    # Deploys and tests regularly run out of memory because they do
    # fork+exec (to run nodejs, etc), and the process they are forking
    # uses a lot of memory, so the fork uses the same amount of memory
    # even though it's immediately replaced by some exec-ed process
    # that uses almost no memory.  This means we have to have twice as
    # much memory available as we actually use: suckasaurus.  The
    # solution is to allow memory overcommitting, which works because
    # the memory in the forked process is never touched (it's
    # immediately freed when we exec).  cf.
    # http://stackoverflow.com/questions/15608347/fork-failing-with-out-of-memory-error
    sudo sysctl vm.overcommit_memory=1

    # Make sure that we've added the info we need to the fstab.
    # ('tee -a' is the way to do '>>' that works with sudo.)
    grep -xqf "$CONFIG_DIR/fstab.extra" /etc/fstab || \
        cat "$CONFIG_DIR/fstab.extra" | sudo tee -a /etc/fstab >/dev/null

    # Make sure all the disks in the fstab are mounted.
    sudo mount -a
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

    # Set the timezone to PST/PDT.  The 'tee' trick writes via sudo.
    echo "America/Los_Angeles" | sudo tee /etc/timezone
    sudo dpkg-reconfigure -f noninteractive tzdata

    # Some KA tests write to /tmp and don't clean up after themselves,
    # on purpose (see kake/server_client.py:rebuild_if_needed().  We
    # install tmpreaper to clean up those files "eventually".
    # This avoids promppting at install time.
    echo "tmpreaper tmpreaper/readsecurity note" | sudo debconf-set-selections
    echo "tmpreaper tmpreaper/readsecurity_upgrading note" | sudo debconf-set-selections
    sudo apt-get install -y tmpreaper
    # We need to comment out a line before tmpreaper will actually run.
    sudo perl -pli -e s/^SHOWWARNING/#SHOWWARNING/ /etc/tmpreaper.conf
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
    sudo gem install bundler

    # jstest deps
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

install_image_tools() {
    echo "Installing image tools"
    # These image tools are used for the Jenkins build that periodically
    # optimizes our image sizes.  danmbox is needed to get pngquant 2.0
    sudo add-apt-repository ppa:danmbox/ppa
    sudo apt-get update
    sudo apt-get install -y pngquant optipng pngcrush libjpeg-turbo-progs
    if [ ! -s /usr/local/bin/pngout ]; then
      ( cd /tmp \
        && wget http://static.jonof.id.au/dl/kenutils/pngout-20130221-linux.tar.gz \
        && tar -zxf pngout-20130221-linux.tar.gz \
        && sudo install -m 755 pngout-20130221-linux/`uname -m`/pngout /usr/local/bin )
    fi
}

install_ubuntu_user_env() {
    sudo cp -av "$CONFIG_DIR/Makefile" "$HOME/"
    make symlinks
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

    # Ensure plugins directory exists.
    sudo -u jenkins mkdir -p "${JENKINS_HOME}"/plugins

    # I created this on a running jenkins install like so (on 7/7/2014):
    # find /var/lib/jenkins/plugins/ -name 'MANIFEST.MF' | xargs grep -h -e Extension-Name -e Plugin-Version | tr -d '\015' | awk 'NR % 2 { n=$2 } NR % 2 == 0 { printf("        \"%s/%s/%s.hpi\" \\\n", n, $2, n) }' | grep -v SNAPSHOT
    for plugin in \
        "any-buildstep/0.1/any-buildstep.hpi" \
        "artifactdeployer/0.29/artifactdeployer.hpi" \
        "mailer/1.8/mailer.hpi" \
        "external-monitor-job/1.2/external-monitor-job.hpi" \
        "timestamper/1.5.12/timestamper.hpi" \
        "ldap/1.10.2/ldap.hpi" \
        "postbuild-task/1.8/postbuild-task.hpi" \
        "token-macro/1.10/token-macro.hpi" \
        "build-user-vars-plugin/1.3/build-user-vars-plugin.hpi" \
        "ec2/1.21/ec2.hpi" \
        "role-strategy/2.2.0/role-strategy.hpi" \
        "antisamy-markup-formatter/1.2/antisamy-markup-formatter.hpi" \
        "simple-theme-plugin/0.3/simple-theme-plugin.hpi" \
        "git-client/1.9.1/git-client.hpi" \
        "throttle-concurrents/1.8.3/throttle-concurrents.hpi" \
        "scm-api/0.2/scm-api.hpi" \
        "translation/1.11/translation.hpi" \
        "flexible-publish/0.12/flexible-publish.hpi" \
        "maven-plugin/2.4/maven-plugin.hpi" \
        "matrix-project/1.2/matrix-project.hpi" \
        "pollscm/1.2/pollscm.hpi" \
        "envinject/1.89/envinject.hpi" \
        "github-api/1.55/github-api.hpi" \
        "node-iterator-api/1.5/node-iterator-api.hpi" \
        "parameterized-trigger/2.25/parameterized-trigger.hpi" \
        "monitoring/1.51.0/monitoring.hpi" \
        "build-name-setter/1.3/build-name-setter.hpi" \
        "build-flow-plugin/0.12/build-flow-plugin.hpi" \
        "cobertura/1.9.5/cobertura.hpi" \
        "github/1.9/github.hpi" \
        "ssh-credentials/1.7.1/ssh-credentials.hpi" \
        "parallel-test-executor/1.4/parallel-test-executor.hpi" \
        "ssh-slaves/1.6/ssh-slaves.hpi" \
        "subversion/2.4/subversion.hpi" \
        "openid4java/0.9.8.0/openid4java.hpi" \
        "mercurial/1.50/mercurial.hpi" \
        "javadoc/1.1/javadoc.hpi" \
        "build-pipeline-plugin/1.4.3/build-pipeline-plugin.hpi" \
        "windows-slaves/1.0/windows-slaves.hpi" \
        "mapdb-api/1.0.1.0/mapdb-api.hpi" \
        "htmlpublisher/1.3/htmlpublisher.hpi" \
        "jenkins-multijob-plugin/1.13/jenkins-multijob-plugin.hpi" \
        "git/2.2.2/git.hpi" \
        "groovy-postbuild/1.9/groovy-postbuild.hpi" \
        "promoted-builds/2.17/promoted-builds.hpi" \
        "ansicolor/0.3.1/ansicolor.hpi" \
        "groovy/1.19/groovy.hpi" \
        "openid/2.1/openid.hpi" \
        "pam-auth/1.1/pam-auth.hpi" \
        "changes-since-last-success/0.5/changes-since-last-success.hpi" \
        "scm-sync-configuration/0.0.7.5/scm-sync-configuration.hpi" \
        "job-poll-action-plugin/1.0/job-poll-action-plugin.hpi" \
        "build-with-parameters/1.1/build-with-parameters.hpi" \
        "disk-usage/0.23/disk-usage.hpi" \
        "rebuild/1.19/rebuild.hpi" \
        "matrix-auth/1.2/matrix-auth.hpi" \
        "credentials/1.14/credentials.hpi" \
        "ant/1.2/ant.hpi" \
        "jquery/1.7.2-1/jquery.hpi" \
        "ssh-agent/1.4.1/ssh-agent.hpi" \
        "jclouds-jenkins/2.8/jclouds-jenkins.hpi" \
        "email-ext/2.38.1/email-ext.hpi" \
        "cvs/2.12/cvs.hpi" \
        "conditional-buildstep/1.3.3/conditional-buildstep.hpi" \
        "run-condition/1.0/run-condition.hpi" \
        ; \
    do
        plugin_url="${jenkins_plugin_url}/${plugin}"
        plugin_file=`basename "${plugin}"`
        plugin_dir=`echo "${plugin_file}" | sed 's/\.hpi//'`
        echo "Fetching $plugin_file plugin from $plugin_url"
        sudo -u jenkins sh -c "cd \"${JENKINS_HOME}\"/plugins && rm -rf \"${plugin_file}\" \"${plugin_dir}\" && wget \"${plugin_url}\""
    done

    # We have a custom hipchat plugin, so do that separately.  We also
    # use a custom version of the ec2 plugin, that is modified to
    # (correctly) support infinite waiting for slaves to come up.
    sudo apt-get install -y maven
    (
        cd /tmp
        git clone https://github.com/chrisklaiber/jenkins-hipchat-plugin.git
        cd jenkins-hipchat-plugin && git checkout khan-custom-plugin
        mkdir -p target/classes
        mvn hpi:hpi -DskipTests
        sudo cp target/hipchat.hpi "${JENKINS_HOME}/plugins/"
        sudo chown jenkins:nogroup "${JENKINS_HOME}/plugins/hipchat.hpi"

        cd /tmp
        git clone https://github.com/Khan/ec2-plugin
        cd ec2-plugin
        mkdir -p target/classes
        mvn package -DskipTests
        sudo cp target/ec2.hpi "${JENKINS_HOME}/plugins/"
        sudo chown jenkins:nogroup "${JENKINS_HOME}/plugins/ec2.hpi"
    )

    # Start the daemon
    sudo update-rc.d jenkins defaults
    sudo service jenkins restart || sudo service jenkins start
}

install_jenkins_user_env() {
    sudo cp -av "$CONFIG_DIR/.gitconfig" "$JENKINS_HOME/"
    sudo cp -av "$CONFIG_DIR/.gitignore_global" "$JENKINS_HOME/"
    sudo cp -av "$CONFIG_DIR/.ssh" "$JENKINS_HOME/"
    sudo chmod 600 "$JENKINS_HOME/.ssh/config"

    # This is needed to fetch from private github repos
    if [ ! -e "$JENKINS_HOME/.ssh/id_rsa.ReadWriteKiln" ]; then
        echo "Copy id_rsa.ReadWriteKiln* from the dropbox Secrets folder to"
        echo "   $JENKINS_HOME/.ssh/"
        echo "Hit enter when done"
        read prompt
    fi
    sudo chmod 600 "$JENKINS_HOME/.ssh/id_rsa.ReadWriteKiln"

    # secrets.py is needed by the translations build and deployment.
    sudo -u jenkins mkdir -p "${SECRETS_DIR}"
    if [ ! -e "$SECRETS_PW" ]; then
        echo "Put the password to decrypt secrets.py on the first line of"
        echo "   $SECRETS_PW"
        echo "See https://www.dropbox.com/home/Khan%20Academy%20All%20Staff/Secrets"
        echo "Hit enter when done"
        read prompt
    fi
    sudo chmod 600 "${SECRETS_PW}"

    # This is needed for the deploy jenkins jobs.
    if [ ! -e "$PROD_SECRETS_PW" ]; then
        echo "Put the prod-deploy secret in $PROD_SECRETS_PW"
        echo "(If you don't know what it is, ask chris or kamens)."
        echo "Hit enter when done"
        read prompt
    fi
    sudo chmod 600 "${PROD_SECRETS_PW}"

    # Make sure we own everything in our homedir
    sudo chown -R jenkins:nogroup "$JENKINS_HOME"
}

install_nginx() {
    echo "Installing nginx"
    sudo apt-get install -y nginx
    sudo rm -f /etc/nginx/sites-enabled/default
    sudo ln -sfnv "${CONFIG_DIR}"/nginx_site_jenkins /etc/nginx/sites-available/jenkins
    sudo ln -sfnv /etc/nginx/sites-available/jenkins /etc/nginx/sites-enabled/jenkins
    sudo service nginx restart
}

install_redis() {
    # We use redis as a simple db to store what tests have passed.
    echo "Installing redis"
    sudo apt-get install -y redis-server
}

install_jenkins_home() {
    # We need the same ssh stuff that jenkins has, to access this private repo.
    sudo rsync -av "$JENKINS_HOME/.ssh/" .ssh/
    sudo chown -R ubuntu:ubuntu .ssh/
    if [ ! -d jenkins_home ]; then
        git clone git@github.com:Khan/jenkins jenkins_home
    fi
    ( cd jenkins_home && git pull && git submodule update --init --recursive )

    # We install jenkins_home/jobs on a separate disk, so sync it separately.
    sudo rsync -av --exclude jobs "jenkins_home/" "${JENKINS_HOME}/"
    sudo chown -R jenkins:nogroup "${JENKINS_HOME}"/*   # avoid dot-files
    # Delete the empty jobs dir jenkins created at setup.
    sudo rmdir "$JENKINS_HOME/jobs"
    if [ -e "${JENKINS_HOME}/jobs" -a ! -L "${JENKINS_HOME}/jobs" ]; then
        echo "Config ERROR: jobs should be a symlink.  Fix manually!"
        exit 1
    fi
    sudo mkdir -p /mnt/jenkins/jobs
    sudo chown -R jenkins:nogroup /mnt/jenkins
    sudo -u jenkins ln -snf /mnt/jenkins/jobs "${JENKINS_HOME}/jobs"
    sudo rsync -av "jenkins_home/jobs/" "${JENKINS_HOME}/jobs/"
    sudo chown -R jenkins:nogroup "${JENKINS_HOME}"/jobs/*
}

update_aws_config_env
install_global_env
install_basic_packages
install_build_deps
install_image_tools
install_jenkins
install_jenkins_user_env
install_ubuntu_user_env   # should happen after jenkins jobs dir is set up
install_nginx
install_redis
install_jenkins_home

echo " TODO: Once restarted, add HIPCHAT_AUTH_TOKEN as a global password:"
echo "       1) Visit http://jenkins.khanacademy.org/configure"
echo "       2) Scroll to 'Global Passwords' section and click 'add'."
echo "       3) Name is 'HIPCHAT_AUTH_TOKEN',"
echo "          password is 'hipchat_notify_token' from secrets.py."

