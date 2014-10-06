#!/bin/sh

# This has files that are used on our internal webserver, that runs on
# ec2.  It has things like the code review tools, the git mirrors,
# etc.
#
# This sets up packages needed on an EC2 machine for
# internal-webserver.  This is based on the Ubuntu11 AMI that Amazon
# provides as one of the default EC2 AMI options.  It is idempotent.
#
# This should be run in the home directory of the role account
# of the user that is to run the internal webserver/etc.  That user
# should be able to sudo to root.
#
# NOTE: This script, along with some of the data files in this
# directory (notably etc/fstab), assume that a 'data' disk has been
# attached to this ec2 instance as sdf (aka xvdf), and that's it's
# been formatted with xfs.

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


install_ec2_tools() {
    # Activate the multiverse!  Needed for ec2-api-tools
    activate_multiverse       # from setup_fns.sh
    sudo apt-get install -y ec2-api-tools
    mkdir -p "$HOME/aws"
    if [ ! -s "$HOME/aws/pk-backup-role-account.pem" ]; then
        echo "Copy the pk-backup-role-account.pem and cert-backup-role-account.pem"
        echo "files from dropbox to $HOME/aws:"
        echo "   https://www.dropbox.com/home/Khan%20Academy%20All%20Staff/Secrets"
        echo "Also, make sure there is an IAM user called 'backup-role-account"
        echo "with permissions from 'backup-role-account-permissions'."
        echo "Then hit enter to continue"
        read prompt
    fi
}

install_repositories() {
    echo "Syncing internal-webserver codebase"
    sudo apt-get install -y git
    git clone git://github.com/Khan/aws-config || \
        ( cd aws-config && git pull && git submodule update --init --recursive )
    git clone git://github.com/Khan/internal-webserver || \
        ( cd internal-webserver && git pull && git submodule update --init --recursive )
}

install_root_config_files_toby() {
    echo "Updating config files on the root filesystem (using symlinks)"
    # This will fail (causing the script to fail) if python isn't
    # python2.7.  If that happens, update the symlinks below to point
    # to the right directory.
    expr "`python --version 2>&1`" : "Python 2\.7" >/dev/null
    sudo ln -snf "$HOME/internal-webserver/python-hipchat/hipchat" \
                 /usr/local/lib/python2.7/dist-packages/

    # Rest is standard'
    install_root_config_files    # from setup_fns.sh
}

install_user_config_files() {
    echo "Creating logs directory (for webserver logs)"
    sudo mkdir -p /opt/logs
    sudo chmod 1777 /opt/logs
    sudo chown www-data.www-data /opt/logs
    ln -snf /opt/logs "$HOME/logs"
    ln -snf /var/tmp/phd/log/daemons.log "$HOME/logs/phd-daemons.log"
    ln -snf /var/log/nginx/error.log "$HOME/logs/nginx-error.log"
}

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

install_phabricator() {
    echo "Installing packages: Phabricator"
    sudo mkdir -p /opt/mysql_data
    ln -snf /opt/mysql_data "$HOME/mysql_data"
    sudo apt-get install -y git mercurial
    sudo apt-get install -y make
    # The envvar here keeps apt-get from prompting for a password.
    # TODO(csilvers): should we give the root mysql user a password?
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server
    sudo apt-get install -y php5 php5-mysql php5-cgi php5-fpm php5-gd php5-curl
    sudo apt-get install -y libpcre3-dev php-pear    # needed to install apc
    # php is dog-slow without APC
    pecl list | grep -q APC || yes "" | sudo pecl install apc
    sudo pip install pygments                      # for syntax highlighting
    sudo ln -snf /usr/local/bin/pygmentize /usr/bin/
    sudo rm -f /etc/nginx/sites-enabled/default
    mkdir -p "$HOME/internal-webserver/phabricator/support/bin"
    cat <<EOF >"$HOME/internal-webserver/phabricator/support/bin/README"
Instead of putting binaries that phabricator needs in your $PATH, you can
put symlinks to them here.  (This directory is in your phabricator-path.)
EOF
    if [ ! -s "/usr/lib/php5/20090626/xhprof.so"]; then
        ( cd /var/tmp
          rm -rf xhprof-0.9.2.tgz xhprof-0.9.2
          wget http://pecl.php.net/get/xhprof-0.9.2.tgz
          tar xfz xhprof-0.9.2.tgz
          rm xhprof-0.9.2.tgz
          cd xhprof-0.9.2/extension
          phpize
          ./configure
          make
          sudo make install
        )
    fi
    echo "SELECT User FROM mysql.user" \
        | mysql --user=root mysql \
        | grep -q phabricator \
    || echo "CREATE USER 'phabricator'@'localhost' IDENTIFIED BY 'codereview'; GRANT ALL PRIVILEGES ON *.* TO 'phabricator'@'localhost' WITH GRANT OPTION;" \
        | mysql --user=root mysql

    # Just in case phabricator is already running (we want to be idempotent!)
    PHABRICATOR_ENV=khan "$HOME/internal-webserver/phabricator/bin/phd" stop
    sudo service nginx stop
    sudo service php5-fpm stop

    env PHABRICATOR_ENV=khan \
        internal-webserver/phabricator/bin/storage --force upgrade

    # TODO(csilvers): automate entering this info:
    cat <<EOF
Enter this info:
    * username: admin
    * real name: Admin Admin
    * email: toby-admin+phabricator@khanacademy.org
    * password: <see secrets.py>
    * system agent: n
    * admin: y
EOF
    env PHABRICATOR_ENV=khan internal-webserver/phabricator/bin/accountadmin

    # Set up the security token
    "$HOME/internal-webserver/arcanist/bin/arc" install-certificate \
        http://phabricator.khanacademy.org/api/

    # We store the repositories on ephemeral disk since they're easy
    # to re-create if need be.
    sudo mkdir -p /mnt/phabricator/repositories
    sudo chmod -R a+rX /mnt/phabricator
    sudo chown -R ubuntu /mnt/phabricator
    ln -snf /mnt/phabricator/repositories "$HOME/phabricator/repositories"
    python "$HOME/internal-webserver/update_phabricator_repositories.py" -v \
        "$HOME/phabricator/repositories"

    # But we store the files on the same disk as mysql so that they get backed
    # up alongside the database data
    sudo mkdir -p /opt/phabricator_files
    sudo chmod -R a+rX /opt/phabricator_files
    sudo chown -R www-data /opt/phabricator_files
    ln -snf /opt/phabricator_files "$HOME/phabricator/files"

    # Start the daemons.
    sudo mkdir -p /var/tmp/phd/log
    sudo chown -R ubuntu /var/tmp/phd
    sudo service php5-fpm start
    sudo service nginx start
    PHABRICATOR_ENV=khan "$HOME/internal-webserver/phabricator/bin/phd" start

    # TODO(csilvers): automate this.
    cat <<EOF
To finish phabricator installation:
1) Visit http://phabricator.khanacademy.org, sign in as admin, visit
   http://phabricator.khanacademy.org/auth/config/new/, and follow
   the directions to enable Google OAuth.
2) Sign out, then sign in again via oauth, create a new account for
   yourself, sign out, sign in as admin, and visit
   http://phabricator.khanacademy.org/people/edit/2/role/
   to make yourself an admin.
3) On AWS's route53 (or whatever), add phabricator-files.khanacademy.org
   as a CNAME to phabricator.khanacademy.org.
EOF
echo "Hit enter when this is done:"
read prompt
}

install_gae_default_version_notifier() {
    echo "Installing gae-default-version-notifier"
    git clone git://github.com/Khan/gae-default-version-notifier.git || \
        ( cd gae-default-version-notifier && git pull && git submodule update --init --recursive )
    # This uses alertlib, so make sure the secret is installed.
    install_alertlib_secret    # from setup_fns.sh
}

install_culture_cow() {
    echo "Installing culture cow"
    git clone git://github.com/Khan/culture-cow.git || \
        ( cd culture-cow && git pull && git submodule update --init --recursive )
    cd culture-cow
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
    git clone git://github.com/Khan/beep-boop.git || \
        ( cd beep-boop && git pull && git submodule update --init --recursive )
    sudo pip install -r beep-boop/requirements.txt
    # This uses alertlib, so make sure the secret is installed.
    install_alertlib_secret    # from setup_fns.sh
    if [ ! -s "$HOME/beep-boop/uservoice.cfg" ]; then
        echo "Put uservoice.cfg in $HOME/beep-boop/."
        echo "This is a file with the contents '<uservoice_api_key>',"
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
    # A simple flask server that will collect youtube oauth credentials needed
    # inorder to upload captions to the various youtube accounts
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
    # A utility to generate exercise icons. Currently used at http://khanacademy.org/commoncore/map.
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
		sudo wget https://phantomjs.googlecode.com/files/phantomjs-1.9.0-linux-x86_64.tar.bz2
		sudo tar -xjf /usr/local/share/phantomjs-1.9.0-linux-x86_64.tar.bz2
		sudo rm /usr/local/share/phantomjs-1.9.0-linux-x86_64.tar.bz2
		sudo ln -sf /usr/local/share/phantomjs-1.9.0-linux-x86_64/bin/phantomjs /usr/local/bin/phantomjs
        fi
        if [ ! -L "/usr/local/bin/casperjs" ]; then
		sudo git clone git://github.com/n1k0/casperjs.git /usr/local/src/casperjs
		cd /usr/local/src/casperjs/
		sudo git fetch origin
		sudo git checkout tags/1.0.2
		sudo ln -snf /usr/local/src/casperjs/bin/casperjs /usr/local/bin/casperjs
        fi

        cd "$HOME"
        git clone git@github.com:Khan/exercise-icons.git || ( cd exercise-icons && git pull && git submodule update --init --recursive )
        if [ ! -e "$HOME/exercise-icons/secrets.txt" ]; then
            echo "Add $HOME/exercise-icons/secrets.txt"
            echo "according to the instructions in README.md."
            echo "BUCKET should be set to 'ka-exercise-screenshots-2'."
            echo "Hit <enter> when this is done:"
            read prompt
        fi
        cd exercise-icons
        make
    )
}

start_daemons() {
    echo "Starting daemons in $HOME/aws-config/internal-webserver/etc/init"
    for daemon in $HOME/aws-config/internal-webserver/etc/init/*.conf; do
        sudo stop `basename $daemon .conf` || true
        sudo start `basename $daemon .conf`
    done
}

cd "$HOME"

update_aws_config_env     # from setup_fns.sh
install_basic_packages    # from setup_fns.sh
install_ec2_tools
install_repositories
install_root_config_files_toby
install_user_config_files
install_appengine
install_phabricator
install_gae_default_version_notifier
install_culture_cow
install_beep_boop
install_gae_dashboard
install_khantube_ouath_collector
install_exercise_icons

# Do this again, just in case any of the apt-get installs nuked it.
install_root_config_files_toby

# Finally, we can start the crontab!
install_crontab    # from setup_fns.sh

echo "Starting daemons"
start_daemons    # from setup_fns.sh
