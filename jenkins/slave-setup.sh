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
. "$HOME"/aws-config/shared/setup_fns.sh

JENKINS_HOME="$HOME"

cd "$HOME"

update_aws_config_env() {
    echo "Update aws-config codebase and installation environment"
    # Make sure the system is up-to-date.
    sudo apt-get update
    sudo apt-get install -y git

    clone_or_update git://github.com/Khan/aws-config
}

install_basic_packages_jenkins() {
    echo "Installing basic packages"

    # I'm not sure why these are 'basic', but I'm afraid to remove them now.
    sudo apt-get install -y ncurses-dev
    sudo apt-get install -y unzip

    # Make sure mail from us is marked as coming from the
    # jenkins-slave, even though our hostname will be 'jenkins' (since
    # this script is run from the 'jenkins' directory).
    export mailsuffix='jenkins-slave-root'

    install_basic_packages   # from setup_fns.sh
}

install_repositories() {
    echo "Syncing git-bigfiles codebase"
    sudo apt-get install -y git
    clone_or_update git://github.com/Khan/aws-config
    clone_or_update git://github.com/Khan/git-bigfile

    # We also need this python file to use git-bigfile
    sudo pip install boto
}

install_jenkins_user_env() {
    sudo cp -av "$CONFIG_DIR/.profile" "$JENKINS_HOME/"
    sudo cp -av "$CONFIG_DIR/.bashrc" "$JENKINS_HOME/"
    sudo cp -av "$CONFIG_DIR/.gitconfig" "$JENKINS_HOME/"
    sudo cp -av "$CONFIG_DIR/.gitignore_global" "$JENKINS_HOME/"
    sudo cp -av "$CONFIG_DIR/.ssh" "$JENKINS_HOME/"
    sudo chmod 600 "$JENKINS_HOME/.ssh/config"

    # Our Jenkins scripts use the 'git new-workdir' command.
    # Until it's standard in git (if ever) we have to install it ourselves.
    clone_or_update https://github.com/Khan/git
    sudo ln -snf "$HOME/git/contrib/workdir/git-new-workdir" /usr/local/bin

    # This is needed to fetch from private github repos.
    install_secret "$JENKINS_HOME/.ssh/id_rsa.ReadWriteKiln" K38
    install_multiline_secret "$JENKINS_HOME/.ssh/id_rsa.ReadWriteKiln.pub" F89990

    # This is needed to use git-bigfile.
    install_secret "$JENKINS_HOME/git-bigfile-storage.secret" K65
}

install_jenkins_slave() {
    echo "Installing Jenkins Slave"

    # get rid of older java
    sudo apt-get purge -y openjdk-6-\*
    # Set up a compatible Java.
    sudo apt-get install -y openjdk-7-jre openjdk-7-jdk
    #ubuntu doesn't use 'default-java' as its way of deciding what
    #java gets used.
    sudo rm /usr/lib/jvm/default-java

    # install a font library needed for some PIL operations
    sudo apt-get install -y libfreetype6 libfreetype6-dev

    mkdir -p webapp-workspace

    # This is the 'canonical' home for webapp (using the git
    # new-workdir structure).
    sudo mkdir -p /var/lib/jenkins
    sudo chown ubuntu.ubuntu /var/lib/jenkins
    mkdir -p /var/lib/jenkins/repositories
}

# This isn't strictly necessary, but it's nice to do before making an
# AMI since it speeds up slave startup time.
setup_webapp() {
    (
        cd /var/lib/jenkins/repositories
        clone_or_update git://github.com/Khan/webapp

        if [ ! -d "$HOME/webapp-workspace/webapp" ]; then
            git new-workdir /var/lib/jenkins/repositories/webapp \
                            "$HOME/webapp-workspace/webapp" \
                            master
        fi
        cd "$HOME/webapp-workspace/webapp"

        git submodule sync
        git submodule init
        # Use new-workdir only for subrepos we know are old and won't
        # be deleted anytime soon; 'new-workdir' doesn't do well with
        # submodules being added and deleted.
        submodules="intl/translations khan-exercises"
        for path in $submodules; do
            [ -f "$path/.git" ] || git new-workdir /var/lib/jenkins/repositories/webapp/"$path" "$path"
        done

        git pull
        git submodule update --init --recursive

        . ../env/bin/activate
        make deps
        make lint      # generate some useful genfiles
    )

    # This also isn't strictly necessary since the jenkins job does it
    # for us, but it's nice to do.
    (
        cd "$HOME/webapp-workspace"
        clone_or_update git://github.com/Khan/jenkins-tools
    )
}


update_aws_config_env            # from setup_fns.sh
install_basic_packages_jenkins
install_repositories
install_root_config_files        # from setup_fns.sh
install_build_deps               # from setup_fns.sh
install_jenkins_user_env
install_jenkins_slave
setup_webapp
