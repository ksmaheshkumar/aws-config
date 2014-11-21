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

    install_basic_packages   # from setup_fns.sh
}

install_jenkins_user_env() {
    cp -av "$CONFIG_DIR/.gitconfig" "$JENKINS_HOME/.gitconfig"
    sudo cp -av "$CONFIG_DIR/.gitignore_global" "$JENKINS_HOME/"
    sudo cp -av "$CONFIG_DIR/.ssh" "$JENKINS_HOME/"
    sudo chmod 600 "$JENKINS_HOME/.ssh/config"

    # This is needed to fetch from private github repos
    if [ ! -e "$JENKINS_HOME/.ssh/id_rsa.ReadWriteKiln" ]; then
        echo "Copy id_rsa.ReadWriteKiln* from the dropbox Secrets folder "
        echo "(or from jenkins:/var/lib/jenkins/.ssh/id_rsa.ReadWriteKiln*) to"
        echo "   $JENKINS_HOME/.ssh/"
        echo "Hit enter when done"
        read prompt
    fi
    sudo chmod 600 "$JENKINS_HOME/.ssh/id_rsa.ReadWriteKiln"
}

install_jenkins_slave() {
    echo "Installing Jenkins Slave"

    # Set up a compatible Java.
    sudo apt-get install -y openjdk-6-jre openjdk-6-jdk
    sudo ln -snf /usr/lib/jvm/java-6-openjdk /usr/lib/jvm/default-java

    mkdir -p webapp-workspace
}

# This isn't strictly necessary, but it's nice to do before making an
# AMI since it speeds up slave startup time.
setup_webapp() {
    (
        cd webapp-workspace
        clone_or_update git://github.com/Khan/webapp
        . env/bin/activate
        cd webapp
        make deps
    )
}


update_aws_config_env            # from setup_fns.sh
install_basic_packages_jenkins
install_root_config_files        # from setup_fns.sh
install_build_deps               # from setup_fns.sh
install_jenkins_user_env
install_jenkins_slave
setup_webapp
