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

# Typically, this is run like this
#
# $ cat setup.sh | ssh <hostname of EC2 machine> sh
#
# WARNING: We've never actually tried to run this script all the way
# through!  Even if it works perfectly, it still has many manual
# steps.  You should definitely be careful running it the first time,
# and treat it more like a README than something you can just run and
# forget.


# Bail on any errors
set -e

sudo apt-get update

install_basic_packages() {
    echo "Installing packages: Basic setup"
    sudo apt-get install -y python-pip
    sudo apt-get install -y ntp
    sudo apt-get install -y lighttpd
    # This is needed so installing postfix doesn't prompt.  See
    # http://www.ossramblings.com/preseed_your_apt_get_for_unattended_installs
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
    sudo cp -sav "$HOME/aws-config/internal-webserver/etc/" /
}

install_user_config_files() {
    echo "Updating dotfiles (using symlinks)"
    cp -sav "$HOME"/internal-webserver/{.hgrc,git-mirrors,hg-mirrors} "$HOME"

    echo "Creating logs directory (for webserver logs)"
    mkdir -p logs && chmod 755 logs && sudo chown www-data.www-data logs

    echo "Installing the crontab"
    crontab aws-config/internal-webserver/crontab

}

install_appengine() {
    # TODO(benkomalo): would be nice to always get the latest version here
    if [ ! -d "/usr/local/google_appengine" ]; then
        echo "Installing appengine"
        ( cd /tmp
          rm -rf google_appengine_1.6.6.zip google_appengine
          wget http://googleappengine.googlecode.com/files/google_appengine_1.6.6.zip
          unzip -o google_appengine_1.6.6.zip
          rm google_appengine_1.6.6.zip
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
        echo "This is the token to type in if kiln-local-backup asks:"
        find ~/.hgcookies | xargs grep fbToken
        # We only need to do this for long enough to get the token.
        timeout 10s python kiln_local_backup .
    )
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
    mkdir -p mysql_data
    sudo apt-get install -y git mercurial
    # The envvar here keeps apt-get from prompting for a password.
    # TODO(csilvers): should we give the root mysql user a password?
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server
    sudo apt-get install -y php5 php5-mysql php5-cgi php5-gd php5-curl
    sudo apt-get install -y libpcre3-dev php-pear    # needed to install apc
    yes "" | sudo pecl install apc            # php is dog-slow without this
    sudo pip install pygments                      # for syntax highlighting
    sudo ln -snf /usr/local/bin/pygmentize /usr/bin/
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
    echo "CREATE USER 'phabricator'@'localhost' IDENTIFIED BY 'codereview'; GRANT ALL PRIVILEGES ON *.* TO 'phabricator'@'localhost' WITH GRANT OPTION;" \
        | mysql --user=root mysql

    env PHABRICATOR_ENV=khan \
        internal-webserver/phabricator/bin/storage --force upgrade
    sed -i s,//setup,, internal-webserver/phabricator/conf/khan.conf.php
    sudo service lighttpd reload
    # TODO(csilvers): automate this somehow?
    echo "Visit phabricator.khanacademy.org and make sure everything is ok."
    echo "Then hit enter to continue"
    read prompt
    ( cd internal-webserver && git checkout phabricator/conf/khan.conf.php )
    sudo service lighttpd reload

    # TODO(csilvers): automate entering this info:
    #   username: admin
    #   real name: Admin Admin
    #   email: toby-admin+phabricator@khanacademy.org
    #   password: <see secrets.py>
    #   admin: y
    env PHABRICATOR_ENV=khan internal-webserver/phabricator/bin/accountadmin

    # Start the daemons.
    mkdir -p "$HOME/phabricator/repositories"
    # TODO(csilvers): this may ask for an hg password to set up the cookie
    rm -rf /tmp/test_repo
    hg clone --noupdate \
        https://khanacademy.kilnhg.com/Code/Mobile-Apps/Group/android \
        /tmp/test_repo
    echo "Here is the token you may need for the next step:"
    find ~/.hgcookies | xargs grep fbToken
    python internal-webserver/update_phabricator_repositories.py -v \
        "$HOME/phabricator/repositories"

    # TODO(csilvers): automate this.
    cat <<EOF
To finish phabricator installation:
1) Follow the instructions at
      internal-webserver/phabricator/conf/custom/khan-google.conf.php
   You should edit this file on the ec2 machine (but not in git!)
2) Visit http://phabricator.khanacademy.org, sign in via oauth,
   create a new account for yourself, sign out, sign in as admin,
   and visit http://phabricator.khanacademy.org/people/edit/2/role/
   to make yourself an admin.
3) On AWS's route53 (or whatever), add phabricator-files.khanacademy.org
   as a CNAME to phabricator.khanacademy.org.
EOF
}

install_jenkins() {
    echo "Installing packages: Jenkins"
    sudo apt-get install -y openjdk-6-jre openjdk-6-jdk

    ## wget -q -O - http://pkg.jenkins-ci.org/debian/jenkins-ci.org.key | sudo apt-key add -
    ## sudo sh -c 'echo deb http://pkg.jenkins-ci.org/debian binary/ > /etc/apt/sources.list.d/jenkins.list'
    ## sudo apt-get update

    sudo apt-get install -y jenkins     # http://jenkins-ci.org

    # For jenkins builds running the website's Makefile.
    sudo apt-get install -y make

    # For jenkins python builds.
    sudo apt-get install -y git mercurial subversion
    sudo pip install virtualenv

    # For tests that rely on Node and Node packages.
    sudo apt-get install -y nodejs
    wget -q -O- http://npmjs.org/install.sh | sudo sh

    # To build a custom version of mercurial-plugin 1.38:
    # With jenkins 1.409.1 installed, a custom version of the
    # Mercurial plugin based on 1.38 should be used to avoid an issue
    # where all committers may be spammed by the build.
    sudo apt-get-install -y maven2
    ( cd internal-webserver/mercurial-plugin
      mvn install
      sudo rm -rf /var/lib/jenkins/plugins/mercurial \
                  /var/lib/jenkins/plugins/mercurial.hpi
      sudo su jenkins -c "cp target/mercurial.hpi /var/lib/jenkins/plugins"
      rm -rf target
    )

    # With jenkins 1.409.1 installed, an older email-ext and its maven
    # dependency are needed.
    sudo su jenkins -c 'cd /var/lib/jenkins/plugins && rm -f email-ext.hpi maven-plugin.hpi && wget http://updates.jenkins-ci.org/download/plugins/email-ext/2.14.1/email-ext.hpi && wget https://updates.jenkins-ci.org/download/plugins/maven-plugin/1.399/maven-plugin.hpi'

    # Start the daemon
    sudo ln -snf /usr/lib/jvm/java-6-openjdk /usr/lib/jvm/default-java
    sudo update-rc.d jenkins defaults
    sudo service jenkins restart

    cat <<EOF
To finish the jenkins install, follow the instructions in jenkins.install.
EOF
}


install_basic_packages
install_repositories
install_root_config_files
install_user_config_files
install_appengine
install_repo_backup
##install_gerrit
install_phabricator
install_jenkins

# Do this again, just in case any of the apt-get installs nuked it.
install_root_config_files
