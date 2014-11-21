#!/bin/sh

# This has files that are used on our phabricator machine, that runs
# our phabricator server on ec2.
#
# This sets up packages needed on an EC2 machine for phabricator.
# This is based on an Ubuntu12.04 AMI.  It is idempotent.
#
# This should be run in the home directory of the role account of the
# user that is to run phabricator.  That user should be able to sudo
# to root.
#
# NOTE: This script, along with some of the data files in this
# directory (notably etc/fstab), assume that a 'data' disk has been
# attached to this ec2 instance as sdf (aka xvdf), and that's it's
# been formatted with xfs.
#
# WARNING: you should definitely be careful running it the first time,
# and treat it more like a README than something you can just run and
# forget.
#
# SECURITY
# --------
# Because we store all our company secrets in the datastore db, this
# ec2 machine is more concerned with security than most.  Here are
# some of the security features of this install:
#
# 1) The ssh private key is protected by a password (TODO(csilvers))
#    and access to that password will be limited to phabricator admins
# 2) The ec2 firewall settings for this machine does not allow access
#    to port 3306, so outsiders cannot access the mysql machine
#    (even if mysql is set to listen to all IPs, which it probably isn't.)
# 3) We set up nginx so all communication to phabricator happens over
#    https.
#
# There are still some unresolved security issues:
# A) The phabricator db is on an aws ebs drive, which an aws admin
#    can access even without permissions.
# B) Likewise, we back up the phabricator db to s3 every night, which
#    someone with appropriate aws permissions could access.
#
# Security feature (2) means that we cannot install the phabricator
# slaves on a separate machine, since they would not be able to
# talk to the db.  If we wanted to do that, we'd have to be much
# more careful about network permissions, mysql passwords, etc.

# Bail on any errors
set -e

CONFIG_DIR="$HOME/aws-config/phabricator"
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
    clone_or_update git://github.com/Khan/aws-config
    # TODO(csilvers): move phabricator stuff to a separate phabricator repo?
    clone_or_update git://github.com/Khan/internal-webserver
}

install_user_config_files() {
    echo "Creating logs directory (for webserver logs)"
    sudo mkdir -p /opt/logs
    sudo chmod 1777 /opt/logs
    sudo chown www-data.www-data /opt/logs
    ln -snf /opt/logs "$HOME/logs"
    ln -snf /var/log/nginx/error.log "$HOME/logs/nginx-error.log"
}

install_phabricator() {
    echo "Installing packages: Phabricator"
    sudo mkdir -p /opt/mysql_data
    ln -snf /opt/mysql_data "$HOME/mysql_data"
    sudo apt-get install -y git mercurial
    sudo apt-get install -y make
    # The envvar here keeps apt-get from prompting for a password.
    # (If we wanted to give the root user a password, we'd do that here.)
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server
    sudo apt-get install -y php5 php5-mysql php5-cgi php5-fpm php5-gd php5-curl
    sudo apt-get install -y libpcre3-dev php-pear    # needed to install apc
    # php is dog-slow without APC
    pecl list | grep -q APC || yes "" | sudo pecl install apc
    sudo pip install pygments                      # for syntax highlighting
    sudo ln -snf /usr/local/bin/pygmentize /usr/bin/
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
        https://phabricator.khanacademy.org/api/

    # Store repositories and files on the same disk as mysql so that
    # they get backed up alongside the database data.
    mkdir -p "$HOME/phabricator"
    sudo mkdir -p /opt/phabricator_repositories
    sudo chmod -R a+rX /opt/phabricator_repositories
    sudo chown -R www-data /opt/phabricator_repositories
    ln -snf /opt/phabricator_repositories "$HOME/phabricator/repositories"

    sudo mkdir -p /opt/phabricator_files
    sudo chmod -R a+rX /opt/phabricator_files
    sudo chown -R www-data /opt/phabricator_files
    ln -snf /opt/phabricator_files "$HOME/phabricator/files"

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
4) Copy ka-wild-13.* from
   https://www.dropbox.com/home/Khan%20Academy%20All%20Staff/Secrets
   to /etc/nginx (as root) and chmod 600 /etc/nginx/ka-wild-13.*.
EOF
echo "Hit enter when this is done:"
read prompt
}


update_aws_config_env     # from setup_fns.sh
install_basic_packages    # from setup_fns.sh
install_ec2_tools
install_repositories
install_root_config_files # from setup_fns.sh
install_user_config_files
install_nginx             # from setup_fns.sh
install_phabricator

# Do this again, just in case any of the apt-get installs nuked it.
install_root_config_files # from setup_fns.sh

# Finally, we can start the crontab!
install_crontab    # from setup_fns.sh

start_daemons    # from setup_fns.sh
