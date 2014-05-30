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

# Activate the multiverse!  Needed for ec2-api-tools
sudo perl -pi.orig -e 'next if /-backports/; s/^# (deb .* multiverse)$/$1/' \
    /etc/apt/sources.list
if ! grep -q nginx/stable /etc/apt/sources.list; then
  sudo add-apt-repository -y "deb http://ppa.launchpad.net/nginx/stable/ubuntu `lsb_release -cs` main"
fi
sudo apt-get update

install_basic_packages() {
    echo "Installing packages: Basic setup"
    sudo apt-get install -y python-pip
    sudo apt-get install -y ntp
    sudo apt-get install -y nginx  # uses ppa added above
    sudo apt-get install -y php5-fpm
    # This is needed so installing postfix doesn't prompt.  See
    # http://www.ossramblings.com/preseed_your_apt_get_for_unattended_installs
    # If it prompts anyway, type in the stuff from postfix.preseed manually.
    sudo apt-get install -y debconf-utils
    sudo debconf-set-selections aws-config/internal-webserver/postfix.preseed
    sudo apt-get install -y postfix

    echo "(Finishing up postfix config)"
    sudo sed -i -e 's/myorigin = .*/myorigin = khanacademy.org/' \
                -e 's/myhostname = .*/myhostname = toby.khanacademy.org/' \
                -e 's/inet_interfaces = all/inet_interfaces = loopback-only/' \
                /etc/postfix/main.cf
    sudo service postfix restart
}

install_ec2_tools() {
    # TODO(csilvers): pip install boto instead.
    sudo apt-get install -y ec2-api-tools
    mkdir -p "$HOME/aws"
    echo "Copy the pk-backup-role-account.pem and cert-backup-role-account.pem"
    echo "files from dropbox to $HOME/aws:"
    echo "   https://www.dropbox.com/home/Khan%20Academy%20All%20Staff/Secrets"
    echo "Also, make sure there is an IAM user called 'backup-role-account"
    echo "with permissions from 'backup-role-account-permissions'."
    echo "Then hit enter to continue"
    read prompt
}

install_repositories() {
    echo "Syncing internal-webserver codebase"
    sudo apt-get install -y git
    git clone git://github.com/Khan/aws-config || \
        ( cd aws-config && git pull )
    git clone git://github.com/Khan/internal-webserver || \
        ( cd internal-webserver && git pull )
}

install_root_config_files() {
    echo "Updating config files on the root filesystem (using symlinks)"
    # This will fail (causing the script to fail) if python isn't
    # python2.7.  If that happens, update the symlinks below to point
    # to the right directory.
    expr "`python --version 2>&1`" : "Python 2\.7" >/dev/null
    sudo ln -snf "$HOME/internal-webserver/python-hipchat/hipchat" \
                 /usr/local/lib/python2.7/dist-packages/

    sudo cp -sav --backup=numbered "$HOME/aws-config/internal-webserver/etc/" /
    sudo chown root:root /etc
    # Make sure that we've added the info we need to the fstab.
    # ('tee -a' is the way to do '>>' that works with sudo.)
    grep -xqf /etc/fstab.extra /etc/fstab || \
        cat /etc/fstab.extra | sudo tee -a /etc/fstab >/dev/null

    # Make sure all the disks in the fstab are mounted.
    sudo mount -a
}

install_user_config_files() {
    echo "Updating dotfiles (using symlinks)"
    cp -sav --backup=numbered "$HOME"/internal-webserver/.hgrc "$HOME"
    # We want the mirrors to live on ephemeral disk: they're easy to
    # re-create if there's need.  And this data is big!
    sudo cp -sav --backup=numbered "$HOME"/internal-webserver/*_mirrors \
        /mnt
    ln -snf /mnt/git_mirrors "$HOME/git_mirrors"
    ln -snf /mnt/hg_mirrors "$HOME/hg_mirrors"

    echo "Creating logs directory (for webserver logs)"
    sudo mkdir -p /opt/logs
    sudo chmod 1777 /opt/logs
    sudo chown www-data.www-data /opt/logs
    ln -snf /opt/logs "$HOME/logs"
    ln -snf /var/tmp/phd/log/daemons.log "$HOME/logs/phd-daemons.log"
}

install_appengine() {
    # TODO(benkomalo): would be nice to always get the latest version here
    sudo apt-get install -y zip
    if [ ! -d "/usr/local/google_appengine" ]; then
        echo "Installing appengine"
        ( cd /tmp
          rm -rf google_appengine_1.7.4.zip google_appengine
          wget http://googleappengine.googlecode.com/files/google_appengine_1.7.4.zip
          unzip -o google_appengine_1.7.4.zip
          rm google_appengine_1.7.4.zip
          sudo mv -T google_appengine /usr/local/google_appengine
        )
    fi
}

install_repo_backup() {
    echo "Installing packages: Mirroring repositories"
    sudo apt-get install -y git mercurial   # for backups
    sudo apt-get install -y fdupes      # for hardlink-ifying kiln repos
    sudo pip install mercurial

    echo "Starting the git daemon"
    # You'll also need to allow access to port 9148 on the ec2 console:
    #    https://console.aws.amazon.com/ec2/home#s=SecurityGroups
    sudo update-rc.d git-daemon defaults
    service git-daemon restart

    echo "Getting permissions for the kiln repository"
    # TODO(csilvers): figure out how to do this automatically.  The
    # 'hg clone' will prompt for a password, and kiln-local-backup may
    # prompt for an API token.
    (
        cd hg_mirrors
        rm -rf /tmp/test_repo
        hg clone --noupdate \
             https://khanacademy.kilnhg.com/Code/Mobile-Apps/Group/android \
             /tmp/test_repo
        # If this doesn't work, make sure there's only one token here.
        token=`find ~/.hgcookies -print0 | xargs -0 grep -h -o 'fbToken.*' \
               | tail -n1 | cut -f2`
        echo "Using kiln token $token"
        # We only need to do this for long enough to cache the token,
        # so future runs of kiln_local_backup.py don't need --token.
        timeout 10s python kiln_local_backup.py \
            --token="$token" --server="khanacademy.kilnhg.com" . \
            || true
    )

    # TODO(csilvers): figure out some way to make sure the user does this...
    echo "Getting permissions for the git repository"
    # Make sure we have a ssh key
    mkdir -p ~/.ssh
    if [ ! -e ~/.ssh/id_rsa ]; then
        ssh-keygen -q -N "" -t rsa -f ~/.ssh/id_rsa
    fi
    # Add khanacademy.kilnhg.com to knownhosts so ssh doesn't prompt.
    ssh -oStrictHostKeyChecking=no khanacademy.kilnhg.com >/dev/null 2>&1 || true
    echo "Visit https://khanacademy.kilnhg.com/Keys"
    echo "Log in as user ReadOnlyKiln (ask kamens for the password),"
    echo "   click 'Add a New Key', paste the contents of $HOME/.ssh/id_rsa.pub"
    echo "   into the box, and hit 'Save key'"
}

install_gerrit() {
    echo "Installing packages: Gerrit"
    sudo apt-get install -y git
    sudo apt-get install -y postgresql
    sudo apt-get install -y openjdk-7-jre-headless git
    # Set up the postgres user.
    # TODO(csilvers): figure out how to not prompt for a password.
    # Will need to use psql directly.  Dunno the right options.  See
    # http://postgresql.1045698.n5.nabble.com/Password-as-a-command-line-argument-to-createuser-td1894162.html
    # password 'codereview'
    sudo su postgres -c 'createuser -A -D -P -E gerrit2 && createdb -E UTF-8 -O gerrit2 reviewdb'

    # Taken from http://gerrit-documentation.googlecode.com/svn/Documentation/2.3/install.html
    # TODO(csilvers): don't prompt for passwords
    sudo passwd mail         # passwd 'smtp'
    sudo adduser gerrit2     # password 'codereview'
    # TODO(csilvers): don't prompt for all this information:
    #   location of git repositories: default
    #   database server type: postgresql, then all default (password 'codereview')
    #   user authentication: default
    #   email delivery: default, smtp username 'mail', password 'smtp'
    #   container process: default
    #   ssh daemon: default
    #   http daemon: default, except url is http://gerrit.khanacademy.org:8080/
    sudo su - gerrit2 -c 'java -jar gerrit-2.3-rc0.war init -d review_site'
    sudo su - gerrit2 -c 'git config --file review_site/etc/gerrit.config auth.type OpenID'
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
    sudo apt-get install -y php5 php5-mysql php5-cgi php5-gd php5-curl
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
    # TODO(csilvers): this may ask for an hg password to set up the cookie
    rm -rf /tmp/test_repo
    hg clone --noupdate \
        https://khanacademy.kilnhg.com/Code/Mobile-Apps/Group/android \
        /tmp/test_repo
    echo "Here is the token you may need for the next step:"
    find ~/.hgcookies | xargs grep -h -o 'fbToken.*'
    python "$HOME/internal-webserver/update_phabricator_repositories.py" -v \
        "$HOME/phabricator/repositories"

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
        ( cd gae-default-version-notifier && git pull )
    echo "For now, set up $HOME/gae-default-version-notifier/secrets.py based"
    echo "on secrets.py.example and the 'real' secrets.py."
    # TODO(csilvers): instead, control this via monit(1).
    echo "Then run: nohup python notify.py </dev/null >/dev/null 2>&1 &"
    echo "Hit <enter> when this is done:"
    read prompt
}


install_beep_boop() {
    echo "Installing beep-boop"
    git clone git://github.com/Khan/beep-boop.git || \
        ( cd beep-boop && git pull )
    sudo pip install -r beep-boop/requirements.txt
    echo "Put hipchat.cfg in beep-boop/ if it's not already there."
    echo "This is a file with the contents 'token = <hipchat id>',"
    echo "where the hipchat id comes from secrets.py."
    echo "Hit <enter> when this is done:"
    read prompt
}

install_publish_notifier() {
    echo "Installing publish-notifier"
    git clone git://github.com/Khan/publish-notifier.git || \
        ( cd publish-notifier && git pull )
    echo "For now, set up $HOME/publish-notifier/secrets.py based"
    echo "on secrets.py.example and the 'real' secrets.py."
    # TODO(csilvers): instead, control this via monit(1).
    echo "Then run: nohup python notify.py </dev/null >/dev/null 2>&1 &"
    echo "Hit <enter> when this is done:"
    read prompt
}

install_kahntube_ouath_collector() {
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
    sudo aptitude -y install gcc-multilib xdg-utils libxml2-dev libcurl4-openssl-dev imagemagick

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
        git clone git@github.com:Khan/exercise-icons.git || (cd exercise-icons && git pull)
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

cd "$HOME"
install_basic_packages
install_ec2_tools
install_repositories
install_root_config_files
install_user_config_files
install_appengine
install_repo_backup
#install_gerrit
install_phabricator
install_gae_default_version_notifier
install_beep_boop
install_publish_notifier
install_kahntube_ouath_collector
install_exercise_icons

# Do this again, just in case any of the apt-get installs nuked it.
install_root_config_files

# Finally, we can start the crontab!
echo "Installing the crontab"
crontab "$HOME/aws-config/internal-webserver/crontab"
