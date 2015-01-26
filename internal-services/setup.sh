#!/bin/sh

# This has files that are used on our internal-services server, that runs on
# ec2. It has things that are needed for our production services, such as
# search.

# Typically, this is run like this
#
# $ cat setup.sh | ssh <hostname of EC2 machine> bash
#
# WARNING: We've never actually tried to run this script all the way
# through!  Even if it works perfectly, it may still have manual
# steps.  You should definitely be careful running it the first time,
# and treat it more like a README than something you can just run and
# forget.


# Bail on any errors
set -e

CONFIG_DIR="$HOME/aws-config/internal-services"
. "$HOME/aws-config/shared/setup_fns.sh"


install_error_monitor_db() {
    echo "Syncing error-monitor-db codebase"
    sudo apt-get install -y git
    clone_or_update git://github.com/Khan/error-monitor-db

    # Need the PPA to get the latest redis-server
    add_ppa chris-lea/redis-server

    sudo apt-get -y install redis-server
    sudo apt-get -y install python-pip python-dev python-numpy python-scipy
    sudo pip install -r "$HOME/error-monitor-db/requirements.txt"

    if [ ! -s "$HOME/error-monitor-db/client_secrets.json" ]; then
        echo "You must install $HOME/error-monitor-db/client_secrets.json."
        echo "To get this, go here and click \"Download JSON\" on the "
        echo "section labeled \"Client ID for native application\":"
        echo "https://console.developers.google.com/project/124072386181/apiui/credential"
        echo "Hit enter when done..."
        read prompt
    fi
    if [ ! -s "$HOME/error-monitor-db/bigquery_credentials.dat" ]; then
        echo "You must provide a login credentials for for BigQuery."
        echo "To get the credentials: cd to $HOME/error-monitor-db,"
        echo "run python bigquery_import.py and follow the instructions."
        echo "(Be sure to login to Google as prod-read@ka.org first!"
        echo "Password is at https://phabricator.khanacademy.org/K7.)"
        echo "Hit enter when done..."
        read prompt
    fi
    install_alertlib_secret    # from setup_fns.sh
}

install_graphie_to_png() {
    echo "Syncing graphie-to-png codebase"
    sudo apt-get install -y git
    clone_or_update git://github.com/Khan/graphie-to-png

    install_npm   # from setup_fns.sh
    # These are needed by some of the pip modules.
    sudo apt-get install -y libxml2-dev libxslt1-dev zlib1g-dev
    sudo pip install -r "$HOME/graphie-to-png/requirements.txt"
    ( cd graphie-to-png && npm install )

    decrypt_secret "$HOME/graphie-to-png/secrets.py" "$CONFIG_DIR/secret.graphie-to-png.cast5" K47
}


cd "$HOME"
update_aws_config_env              # from setup_fns.sh
install_basic_packages    # from setup_fns.sh
install_error_monitor_db
install_graphie_to_png
install_root_config_files          # from setup_fns.sh
install_user_config_files          # from setup_fns.sh
install_nginx                      # from setup_fns.sh

# Finally, we can start the crontab!
install_crontab    # from setup_fns.sh

# Start the daemons!
start_daemons                      # from setup_fns.sh
