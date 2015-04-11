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
. "$HOME"/aws-config/shared/setup_fns.sh

# These are files that would be installed because they live in
# ../shared, that you don't want installed on this machine.  e.g.
# if you really didn't want the OOM detector or foo cronjobs running
# on this machine, you could list "etc/cron.d/oom-detector.tpl etc/cron.d/foo"
SHARED_FILE_EXCLUDES=""

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

install_basic_packages_jenkins() {
    echo "Installing basic packages"

    # I'm not sure why these are 'basic', but I'm afraid to remove them now.
    sudo apt-get install -y ncurses-dev
    sudo apt-get install -y unzip

    install_basic_packages   # from setup_fns.sh
}

install_repositories() {
    echo "Syncing git-bigfiles codebase"
    sudo apt-get install -y git
    clone_or_update git://github.com/Khan/aws-config
    clone_or_update git://github.com/Khan/git-bigfile
    # git-bigfile is run by jenkins, so we need to install it as the
    # jenkins user so it can auto-update.
    sudo rm -rf "$JENKINS_HOME/git-bigfile"
    sudo mv git-bigfile "$JENKINS_HOME/"
    sudo chown -R jenkins:nogroup "$JENKINS_HOME/git-bigfile"

    # We also need this python file to use git-bigfile
    sudo pip install boto
}

install_root_config_files_jenkins() {
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

    # Our Jenkins scripts use the 'git new-workdir' command.
    # Until it's standard in git (if ever) we have to install it ourselves.
    clone_or_update https://github.com/Khan/git
    sudo ln -snf "$HOME/git/contrib/workdir/git-new-workdir" /usr/local/bin

    # Rest is standard.
    install_root_config_files   # from setup_fns.sh
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

    # We don't want the security cronjob to automatically update
    # jenkins whenever there's a reported security hole (updating
    # jenkins, along with its plugins, is a delicate process, and we
    # can't automate it!)
    sudo apt-mark hold jenkins

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
        clone_or_update https://github.com/chrisklaiber/jenkins-hipchat-plugin.git
        cd jenkins-hipchat-plugin && git checkout khan-custom-plugin
        mkdir -p target/classes
        mvn hpi:hpi -DskipTests
        sudo cp target/hipchat.hpi "${JENKINS_HOME}/plugins/"
        sudo chown jenkins:nogroup "${JENKINS_HOME}/plugins/hipchat.hpi"

        cd /tmp
        clone_or_update https://github.com/Khan/ec2-plugin
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
    sudo cp -av "$CONFIG_DIR/.profile" "$JENKINS_HOME/"
    sudo cp -av "$CONFIG_DIR/.bashrc" "$JENKINS_HOME/"
    sudo cp -av "$CONFIG_DIR/.gitconfig" "$JENKINS_HOME/"
    sudo cp -av "$CONFIG_DIR/.gitignore_global" "$JENKINS_HOME/"
    sudo cp -av "$CONFIG_DIR/.ssh" "$JENKINS_HOME/"
    sudo chmod 600 "$JENKINS_HOME/.ssh/config"

    # We chown to ensure install_secret_* will work.  We'll change the
    # owner (back) to jenkins below.
    sudo mkdir -p "${SECRETS_DIR}" "$JENKINS_HOME"/.ssh
    sudo chown -R ubuntu "${SECRETS_DIR}" "$JENKINS_HOME"/.ssh

    # This is needed to fetch from private github repos.
    install_secret "$JENKINS_HOME/.ssh/id_rsa.ReadWriteKiln" K38
    install_multiline_secret "$JENKINS_HOME/.ssh/id_rsa.ReadWriteKiln.pub" F89990
    # This is needed to use git-bigfile.
    install_secret "$JENKINS_HOME/git-bigfile-storage.secret" K65
    # secrets.py is needed by the translations build and deployment.
    install_secret_from_secrets_py "$SECRETS_PW" secrets_secrets
    install_secret "$PROD_SECRETS_PW" K43

    # Make sure we own everything in our homedir.
    sudo chown -R jenkins:nogroup "$JENKINS_HOME"
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
    clone_or_update git@github.com:Khan/jenkins jenkins_home

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

    # We also set up jenkins_home/repositories, which will be the home
    # of the git repositories that our jobs use.
    sudo -u jenkins mkdir -p /mnt/jenkins/repositories
    sudo -u jenkins ln -snf /mnt/jenkins/repositories "${JENKINS_HOME}/repositories"
}

install_dropbox() {
    cd ~ && wget -O - "https://www.dropbox.com/download?plat=lnx.x86_64" | tar xzf -
    # Get the cli that we can use to check the status of dropbox to make sure 
    # files are up-to-date
    wget https://linux.dropbox.com/packages/dropbox.py
    chmod 0755 dropbox.py
    sudo mv dropbox.py /bin/

    # Set up a dropbox directory on mnt as the partition home is in is too small.
    sudo mkdir -p /mnt/dropbox
    sudo chown -R ubuntu:ubuntu /mnt/dropbox
    
    # If this computer hasn't been synched yet with dropbox, dropboxd outputs:
    # Please visit https://www.dropbox.com/cli_link_nonce?nonce=26... to link this device
    echo "Follow the instructions from dropbox below to link this account to jenkins@khanacademy.org"
    echo "The password can be found at https://phabricator.khanacademy.org/K51"
    echo "If you don't see a message then this computer has already been linked to the dropbox account and you can just press enter to continue."
    HOME=/mnt/dropbox ~/.dropbox-dist/dropboxd &
    read prompt
    HOME=/mnt/dropbox dropbox.py status
}

update_aws_config_env    # from setup_fns.sh
install_basic_packages_jenkins
install_repositories
install_root_config_files_jenkins
install_build_deps       # from setup_fns.sh
install_jenkins
install_jenkins_user_env
install_ubuntu_user_env   # should happen after jenkins jobs dir is set up
install_nginx   # from setup_fns.sh
install_redis
install_jenkins_home
install_dropbox

echo " TODO: Once restarted, add HIPCHAT_AUTH_TOKEN as a global password:"
echo "       1) Visit http://jenkins.khanacademy.org/configure"
echo "       2) Scroll to 'Global Passwords' section and click 'add'."
echo "       3) Name is 'HIPCHAT_AUTH_TOKEN',"
echo "          password is 'hipchat_notify_token' from secrets.py."

