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

install_user_config_files() {
    echo "Creating logs directory (for misc service logs)"
    sudo mkdir -p $HOME/logs
    sudo chmod 1777 $HOME/logs
}

# TODO(csilvers): do we still need this?
install_appengine() {
    if [ -d "/usr/local/google_appengine" ]; then
        ( cd /usr/local/frankenserver && sudo git pull && sudo git submodule update --init --recursive )
    else
        echo "Installing frankenserver appengine"
        ( cd /usr/local
          sudo clone_or_update https://github.com/Khan/frankenserver
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
    cd culture-cow
    install_npm     # from setup_fns.sh
    npm install
    if [ ! -s "$HOME/culture-cow/bin/secrets" ]; then
        echo "Put secrets in $HOME/culture-cow/bin."
        echo "This is a shell script that lives in dropbox:"
        echo "   https://www.dropbox.com/home/Khan%20Academy%20All%20Staff/Secrets/culture%20cow"
        echo "and contains keys for connecting to hipchat and trello."
        echo "Hit <enter> when this is done:"
        read prompt
    fi
}

install_beep_boop() {
    echo "Installing beep-boop"
    clone_or_update git://github.com/Khan/beep-boop.git
    sudo pip install -r beep-boop/requirements.txt
    # This uses alertlib, so make sure the secret is installed.
    install_alertlib_secret    # from setup_fns.sh
    if [ ! -s "$HOME/beep-boop/zendesk.cfg" ]; then
        echo "Put zendesk.cfg in $HOME/beep-boop/."
        echo "This is a file with the contents '<zendesk_api_key>',"
        echo "where the api key comes from secrets.py."
        echo "Hit <enter> when this is done:"
        read prompt
    fi
}

install_gae_dashboard() {
    # gnuplot is used in email_bq_data
    sudo apt-get install -y python-dev libxml2-dev libxslt1-dev gnuplot
    sudo pip install lxml cssselect        # to parse GAE dashboard output
    sudo pip install GChartWrapper
    if [ ! -s "$HOME/hostedgraphite_secret" ]; then
        echo "Put the value of hostedgraphite_api_key from secrets.py"
        echo "in $HOME/hostedgraphite_secret"
        echo "Hit <enter> when this is done:"
        read prompt
    fi
    if [ ! -s "$HOME/private_pw" ]; then
        echo "Put the password for khanbackups@gmail.com"
        echo "in $HOME/private_pw"
        echo "Hit <enter> when this is done:"
        read prompt
    fi

    sudo pip install bigquery              # to report from BigQuery
    khan_project_id=124072386181
    bq_credential_file="$HOME/.bigquerv2.token"
    if [ ! -s "$bq_credential_file" ]; then
        echo "Log into Google as the user prod-read@khanacademy.org,"
        echo "the password is in secrets.py."
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
    if [ ! -e "$HOME/internal-webserver/khantube-oauth-collector/secrets.py" ]; then
        echo "Add $HOME/internal-webserver/khantube-oauth-collector/secrets.py "
        echo "according to the secrets_example.py in the same directory."
        echo "Hit <enter> when this is done:"
        read prompt
    fi
    sudo service khantube-oauth-collector-daemon restart
}

install_exercise_icons() {
    # A utility to generate exercise icons. Currently used at
    # http://khanacademy.org/commoncore/map.
    # https://github.com/Khan/exercise-icons/
    sudo apt-get install -y gcc-multilib xdg-utils libxml2-dev libcurl4-openssl-dev imagemagick

    if [ ! -e "/usr/bin/dmd" ]; then
        wget http://downloads.dlang.org/releases/2014/dmd_2.065.0-0_amd64.deb -O /tmp/dmd.deb
        sudo dpkg -i /tmp/dmd.deb
        rm /tmp/dmd.deb
    fi

    (
        cd /usr/local/share

        if [ ! -L "/usr/local/bin/phantomjs" ]; then
            sudo wget https://phantomjs.googlecode.com/files/phantomjs-1.9.8-linux-x86_64.tar.bz2
            sudo tar -xjf /usr/local/share/phantomjs-1.9.8-linux-x86_64.tar.bz2
            sudo rm /usr/local/share/phantomjs-1.9.8-linux-x86_64.tar.bz2
            sudo ln -sf /usr/local/share/phantomjs-1.9.8-linux-x86_64/bin/phantomjs /usr/local/bin/phantomjs
        fi
        if [ ! -L "/usr/local/bin/casperjs" ]; then
            sudo clone_or_update git://github.com/n1k0/casperjs.git /usr/local/src/casperjs
            cd /usr/local/src/casperjs/
            sudo git fetch origin
            sudo git checkout tags/1.0.2
            sudo ln -snf /usr/local/src/casperjs/bin/casperjs /usr/local/bin/casperjs
        fi

        cd "$HOME"
        clone_or_update git@github.com:Khan/exercise-icons.git
        if [ ! -e "$HOME/exercise-icons/full-run.sh" ]; then
            echo "Add $HOME/exercise-icons/full-run.sh by copying and modifying"
            echo "$HOME/exercise-icons/full-run.sh.example."
            echo "S3_BUCKET should be set to 'ka-exercise-screenshots-3'."
            echo "Hit <enter> when this is done:"
            read prompt
        fi
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
install_user_config_files
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
