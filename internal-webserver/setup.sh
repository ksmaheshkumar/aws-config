#!/bin/sh

# This has files that are used on our internal webserver, that runs on
# ec2.  It has misc services that run for us, such as culture-cow.
#
# This sets up packages needed on an EC2 machine for
# internal-webserver.  This is based on an Ubuntu12.04 AMI.  It is
# idempotent.
#
# This should be run in the home directory of the role account
# of the user that is to run the internal webserver/etc.  That user
# should be able to sudo to root.

# Typically, this is run like this
#
# $ cat setup.sh | ssh <hostname of EC2 machine> bash
#
# WARNING: We've never actually tried to run this script all the way
# through!  Even if it works perfectly, it still has many manual
# steps.  You should definitely be careful running it the first time,
# and treat it more like a README than something you can just run and
# forget.


# Bail on any errors
set -e

CONFIG_DIR="$HOME/aws-config/internal-webserver"
. "$HOME/aws-config/shared/setup_fns.sh"


install_repositories() {
    echo "Syncing internal-webserver codebase"
    sudo apt-get install -y git
    clone_or_update git://github.com/Khan/aws-config
    clone_or_update git://github.com/Khan/internal-webserver
}

install_user_config_files_toby() {
    echo "Creating logs directory (for misc service logs)"
    # We want to keep the toby logs around forever, not put them on
    # ephemeral disk, so we do a mkdir ourselves before calling
    # our parent.
    mkdir -p $HOME/logs
    install_user_config_files    # from setup_fns.sh
}

# TODO(csilvers): do we still need this?
install_appengine() {
    if [ -d "/usr/local/google_appengine" ]; then
        ( cd /usr/local/frankenserver && sudo git pull && sudo git submodule update --init --recursive )
    else
        echo "Installing frankenserver appengine"
        ( cd /usr/local
          sudo git clone https://github.com/Khan/frankenserver
          sudo ln -snf frankenserver/python google_appengine
        )
    fi
}

install_gae_default_version_notifier() {
    echo "Installing gae-default-version-notifier"
    clone_or_update git://github.com/Khan/gae-default-version-notifier.git
    # This uses alertlib, so make sure the secret is installed.
    install_alertlib_secret    # from setup_fns.sh
}

install_culture_cow() {
    echo "Installing culture cow"
    clone_or_update git://github.com/Khan/culture-cow.git
    install_npm     # from setup_fns.sh
    ( cd culture-cow && npm install )
    decrypt_secret "$HOME/culture-cow/bin/secrets" "$CONFIG_DIR/secrets.culture_cow.cast5" K40
}

install_beep_boop() {
    echo "Installing beep-boop"
    clone_or_update git://github.com/Khan/beep-boop.git
    sudo pip install -r beep-boop/requirements.txt
    # This uses alertlib, so make sure the secret is installed.
    install_alertlib_secret    # from setup_fns.sh
    install_secret "$HOME/beep-boop/zendesk.cfg" K20
}

install_gae_dashboard() {
    # gnuplot is used in email_bq_data
    sudo apt-get install -y python-dev libxml2-dev libxslt1-dev gnuplot
    sudo pip install lxml cssselect        # to parse GAE dashboard output
    sudo pip install GChartWrapper
    install_secret_from_secrets_py "$HOME/hostedgraphite_secret" hostedgraphite_api_key
    install_secret "$HOME/private_pw" K41  # kabackups@gmail.com password

    sudo pip install ez_setup              # needed to install bigquery
    sudo pip install bigquery              # to report from BigQuery
    khan_project_id=124072386181
    bq_credential_file="$HOME/.bigquery.v2.token"
    if [ ! -s "$bq_credential_file" ]; then
        echo "Log into Google as the user prod-read@khanacademy.org,"
        echo "the password is at https://phabricator.khanacademy.org/K7."
        echo "Hit <enter> when this is done.  The next prompt will"
        echo "have you visit a URL as prod-read and get an auth code."
        read prompt
        bq ls --project_id="$khan_project_id" --credential_file="$bq_credential_file"
    fi
}

install_khantube_ouath_collector() {
    # A simple flask server that will collect youtube oauth
    # credentials needed in order to upload captions to the various
    # youtube accounts
    sudo pip install -r "${HOME}"/internal-webserver/khantube-oauth-collector/requirements.txt
    sudo update-rc.d -f khantube-oauth-collector-daemon remove
    sudo ln -snf "${HOME}"/aws-config/internal-webserver/etc/init.d/khantube-oauth-collector-daemon /etc/init.d
    sudo update-rc.d khantube-oauth-collector-daemon defaults

    install_secret_from_secrets_py "$HOME/internal-webserver/khantube-oauth-collector/secrets.py" khantube_client_id
    install_secret_from_secrets_py "$HOME/internal-webserver/khantube-oauth-collector/secrets.py" khantube_client_secret

    sudo service khantube-oauth-collector-daemon restart
}

install_exercise_icons() {
    # A utility to generate exercise icons. Currently used at
    # http://khanacademy.org/commoncore/map.
    # https://github.com/Khan/exercise-icons/
    sudo apt-get install -y gcc-multilib xdg-utils libxml2-dev libcurl4-openssl-dev imagemagick graphicsmagick

    if [ ! -e "/usr/bin/dmd" ]; then
        wget http://downloads.dlang.org/releases/2014/dmd_2.065.0-0_amd64.deb -O /tmp/dmd.deb
        sudo dpkg -i /tmp/dmd.deb
        rm /tmp/dmd.deb
    fi

    (
        cd /usr/local/share

        if [ ! -L "/usr/local/bin/phantomjs" ]; then
            sudo wget https://bitbucket.org/ariya/phantomjs/downloads/phantomjs-1.9.8-linux-x86_64.tar.bz2
            sudo tar -xjf /usr/local/share/phantomjs-1.9.8-linux-x86_64.tar.bz2
            sudo rm /usr/local/share/phantomjs-1.9.8-linux-x86_64.tar.bz2
            sudo ln -sf /usr/local/share/phantomjs-1.9.8-linux-x86_64/bin/phantomjs /usr/local/bin/phantomjs
        fi
        if [ ! -L "/usr/local/bin/casperjs" ]; then
            sudo git clone git://github.com/n1k0/casperjs.git /usr/local/src/casperjs
            cd /usr/local/src/casperjs/
            sudo git fetch origin
            sudo git checkout tags/1.0.2
            sudo ln -snf /usr/local/src/casperjs/bin/casperjs /usr/local/bin/casperjs
        fi

        cd "$HOME"
        clone_or_update http://github.com/Khan/exercise-icons
        decrypt_secret "$HOME/exercise-icons/secrets.sh" "$CONFIG_DIR/secrets.exercise_icons.cast5" K42
        cd exercise-icons
        make
        install_npm     # from setup_fns.sh
        npm install
    )
}

cd "$HOME"

update_aws_config_env     # from setup_fns.sh
install_basic_packages    # from setup_fns.sh
install_repositories
install_root_config_files # from setup_fns.sh
install_user_config_files_toby
install_nginx             # from setup_fns.sh
install_appengine
install_gae_default_version_notifier
install_culture_cow
install_beep_boop
install_gae_dashboard
install_khantube_ouath_collector
install_exercise_icons

# Do this again, just in case any of the apt-get installs nuked it.
install_root_config_files # from setup_fns.sh

# Finally, we can start the crontab!
install_crontab    # from setup_fns.sh

start_daemons    # from setup_fns.sh
