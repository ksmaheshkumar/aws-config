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

install_ec2_tools() {
    # Activate the multiverse!  Needed for ec2-api-tools
    activate_multiverse       # from setup_fns.sh
    sudo apt-get install -y ec2-api-tools
    install_multiline_secret "$HOME/aws/pk-backup-role-account.pem" K44
    install_multiline_secret "$HOME/aws/cert-backup-role-account.pem" F89983
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


    jenkins_cli_jar="${HOME}"/bin/jenkins-cli.jar
    jenkins_plugin_url=http://updates.jenkins-ci.org/download/plugins

    # Instructions for installing on Ubuntu are from
    # https://wiki.jenkins-ci.org/display/JENKINS/Installing+Jenkins+on+Ubuntu
    sudo apt-key add "${CONFIG_DIR}"/jenkins-ci.org.key
    sudo sh -c 'echo deb http://pkg.jenkins-ci.org/debian binary/ >/etc/apt/sources.list.d/jenkins.list'
    sudo apt-get update


    # Set up a compatible Java.
    sudo apt-get install -y openjdk-7-jre openjdk-7-jdk

    sudo apt-get install -y jenkins     # http://jenkins-ci.org

    # install a font library needed for some PIL operations
    sudo apt-get install -y libfreetype6 libfreetype6-dev

    # We don't want the security cronjob to automatically update
    # jenkins whenever there's a reported security hole (updating
    # jenkins, along with its plugins, is a delicate process, and we
    # can't automate it!)
    sudo apt-mark hold jenkins

    # Ensure plugins directory exists.
    sudo -u jenkins mkdir -p "${JENKINS_HOME}"/plugins

    # I created this on a running jenkins install like so (on 8/13/2015):
    # find /var/lib/jenkins/plugins/ -name 'MANIFEST.MF' | xargs grep -h -e Extension-Name -e Plugin-Version | tr -d '\015' | awk 'NR % 2 { n=$2 } NR % 2 == 0 { printf("        \"%s/%s/%s.hpi\" \\\n", n, $2, n) }' | grep -v SNAPSHOT | sort
    for plugin in \
        "ansicolor/0.4.1/ansicolor.hpi" \
        "ant/1.2/ant.hpi" \
        "antisamy-markup-formatter/1.3/antisamy-markup-formatter.hpi" \
        "any-buildstep/0.1/any-buildstep.hpi" \
        "artifactdeployer/0.33/artifactdeployer.hpi" \
        "build-flow-plugin/0.18/build-flow-plugin.hpi" \
        "build-name-setter/1.3/build-name-setter.hpi" \
        "build-pipeline-plugin/1.4.7/build-pipeline-plugin.hpi" \
        "build-timeout/1.15/build-timeout.hpi" \
        "build-token-root/1.3/build-token-root.hpi" \
        "build-user-vars-plugin/1.4/build-user-vars-plugin.hpi" \
        "build-with-parameters/1.3/build-with-parameters.hpi" \
        "changes-since-last-success/0.5/changes-since-last-success.hpi" \
        "cobertura/1.9.7/cobertura.hpi" \
        "conditional-buildstep/1.3.3/conditional-buildstep.hpi" \
        "credentials/1.22/credentials.hpi" \
        "cvs/2.12/cvs.hpi" \
        "disk-usage/0.25/disk-usage.hpi" \
        "durable-task/1.6/durable-task.hpi" \
        "ec2/1.29/ec2.hpi" \
        "email-ext/2.40.5/email-ext.hpi" \
        "envinject/1.91.4/envinject.hpi" \
        "external-monitor-job/1.4/external-monitor-job.hpi" \
        "flexible-publish/0.15.2/flexible-publish.hpi" \
        "git/2.4.0/git.hpi" \
        "git-client/1.18.0/git-client.hpi" \
        "github/1.12.1/github.hpi" \
        "github-api/1.69/github-api.hpi" \
        "git-server/1.6/git-server.hpi" \
        "google-login/1.1/google-login.hpi" \
        "groovy/1.27/groovy.hpi" \
        "groovy-postbuild/2.2/groovy-postbuild.hpi" \
        "hipchat/0.1.9/hipchat.hpi" \
        "htmlpublisher/1.5/htmlpublisher.hpi" \
        "javadoc/1.3/javadoc.hpi" \
        "jclouds-jenkins/2.8/jclouds-jenkins.hpi" \
        "jenkins-multijob-plugin/1.16/jenkins-multijob-plugin.hpi" \
        "job-poll-action-plugin/1.0/job-poll-action-plugin.hpi" \
        "jquery/1.11.2-0/jquery.hpi" \
        "junit/1.8/junit.hpi" \
        "ldap/1.11/ldap.hpi" \
        "mailer/1.15/mailer.hpi" \
        "mapdb-api/1.0.6.0/mapdb-api.hpi" \
        "matrix-auth/1.2/matrix-auth.hpi" \
        "matrix-project/1.6/matrix-project.hpi" \
        "maven-plugin/2.11/maven-plugin.hpi" \
        "mercurial/1.54/mercurial.hpi" \
        "monitoring/1.56.0/monitoring.hpi" \
        "node-iterator-api/1.5/node-iterator-api.hpi" \
        "openid/2.1.1/openid.hpi" \
        "openid4java/0.9.8.0/openid4java.hpi" \
        "pam-auth/1.2/pam-auth.hpi" \
        "parallel-test-executor/1.7/parallel-test-executor.hpi" \
        "parameterized-trigger/2.28/parameterized-trigger.hpi" \
        "pollscm/1.2/pollscm.hpi" \
        "postbuild-task/1.8/postbuild-task.hpi" \
        "promoted-builds/2.21/promoted-builds.hpi" \
        "rebuild/1.25/rebuild.hpi" \
        "role-strategy/2.2.0/role-strategy.hpi" \
        "run-condition/1.0/run-condition.hpi" \
        "scm-api/0.2/scm-api.hpi" \
        "scm-sync-configuration/0.0.8/scm-sync-configuration.hpi" \
        "script-security/1.14/script-security.hpi" \
        "simple-theme-plugin/0.3/simple-theme-plugin.hpi" \
        "ssh-agent/1.8/ssh-agent.hpi" \
        "ssh-credentials/1.11/ssh-credentials.hpi" \
        "ssh-slaves/1.10/ssh-slaves.hpi" \
        "subversion/2.5.1/subversion.hpi" \
        "throttle-concurrents/1.8.4/throttle-concurrents.hpi" \
        "timestamper/1.7.1/timestamper.hpi" \
        "token-macro/1.10/token-macro.hpi" \
        "translation/1.12/translation.hpi" \
        "windows-slaves/1.1/windows-slaves.hpi" \
        "workflow-aggregator/1.9/workflow-aggregator.hpi" \
        "workflow-api/1.9/workflow-api.hpi" \
        "workflow-basic-steps/1.9/workflow-basic-steps.hpi" \
        "workflow-cps/1.9/workflow-cps.hpi" \
        "workflow-cps-global-lib/1.9/workflow-cps-global-lib.hpi" \
        "workflow-durable-task-step/1.9/workflow-durable-task-step.hpi" \
        "workflow-job/1.9/workflow-job.hpi" \
        "workflow-scm-step/1.9/workflow-scm-step.hpi" \
        "workflow-step-api/1.9/workflow-step-api.hpi" \
        "workflow-stm/0.1-beta-3/workflow-stm.hpi" \
        "workflow-support/1.9/workflow-support.hpi" \
        ; \
    do
        plugin_url="${jenkins_plugin_url}/${plugin}"
        plugin_file=`basename "${plugin}"`
        plugin_dir=`echo "${plugin_file}" | sed 's/\.hpi//'`
        echo "Fetching $plugin_file plugin from $plugin_url"
        sudo -u jenkins sh -c "cd \"${JENKINS_HOME}\"/plugins && rm -rf \"${plugin_file}\" \"${plugin_dir}\" && wget \"${plugin_url}\""
    done

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

install_gsutil_and_gcloud() {
    # If there is already a configuration file for gsutil, skip this step.
    # Note that `gsutil config` writes its config file to ~/.boto by default.
    if [ ! -e "$JENKINS_HOME"/.boto ]; then
        sudo apt-get install libffi-dev    # needed by gsutil
        sudo pip install gsutil

        echo "---------------------------------------------------------------"
        echo "The following steps allow Jenkins to be authenticated to Google"
        echo "Cloud Storage via gsutil."

        echo "When creating your gsutil credentials, use the"
        echo "prod-deploy@khanacademy.org account:"
        echo "    https://phabricator.khanacademy.org/K43"
        echo "The project-id is: 124072386181"
        echo "---------------------------------------------------------------"

        # Interactive prompt which creates a config file at ~/.boto
        sudo -u jenkins -i gsutil config
    fi

    if [ ! -e "$HOME/google-cloud-sdk" ]; then
        # Sadly the pip package for gcloud doesn't install the binary :-(
        wget https://dl.google.com/dl/cloudsdk/release/google-cloud-sdk.tar.gz
        tar xfz google-cloud-sdk.tar.gz
        chmod -R a+rX google-cloud-sdk
        yes | ./google-cloud-sdk/install.sh
        GCLOUD="$HOME/google-cloud-sdk/bin/gcloud"
        yes | "$GCLOUD" preview app || true
    fi

    if [ ! -d "$JENKINS_HOME/.config/gcloud" ]; then
        echo "---------------------------------------------------------------"
        echo "The following steps allow Jenkins to be authenticated to Google"
        echo "Cloud via gcloud."

        echo "When creating your gcloud credentials, use the"
        echo "prod-deploy@khanacademy.org account:"
        echo "    https://phabricator.khanacademy.org/K43"
        echo "---------------------------------------------------------------"

        # Interactive prompt which creates a config file at ~/.config/gcloud
        sudo -u jenkins -i gcloud auth login
    fi
}



update_aws_config_env    # from setup_fns.sh
install_basic_packages_jenkins
install_ec2_tools
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
install_gsutil_and_gcloud
