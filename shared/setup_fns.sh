# Source this file to get setup functions shared across machine-types.
# Most of these setup scripts are ubuntu-specific.  They may even be
# ubuntu12 specified.

# You must have $CONFIG_DIR set before sourcing this file.  It should
# point to $PWD/aws-config/<your_machine_type>.  It must be an
# absolute path.
if [ -z "$CONFIG_DIR" ]; then
   echo "You must set CONFIG_DIR before sourcing setup_fns.sh"
   exit 1
fi

if ! expr "$CONFIG_DIR" : / 2>/dev/null; then
   echo "CONFIG_DIR must be an absolute path, not '$CONFIG_DIR'."
   exit 1
fi

# $1: an absolute file like $CONFIG_DIR/etc/foo.  Returns /etc/foo.
# $2 (optional): Value to use instead of CONFIG_DIR
_to_fs() {
   echo "$1" | sed "s,^${2-$CONFIG_DIR},,"
}


# $1: name of the ppa, eg. "chris-lea/node.js"
add_ppa() {
    if ! ls /etc/apt/sources.list.d/ 2>&1 | grep -q `echo $1 | tr / .`; then
        sudo add-apt-repository -y ppa:"$1"
        sudo apt-get update
   fi
 }

# $1: the url of the repo to clone.  $2 (optional): dir to clone to.
clone_or_update() {
    dir="${2-"`basename $1 .git`"}"
    if [ -d "$dir" ]; then
        ( cd "$dir" && git pull && git submodule update --init --recursive )
    else
        git clone --recursive "$1" "$dir"
    fi
}

update_aws_config_env() {
    echo "Update aws-config codebase and installation environment"
    # To get the most recent git, later.
    add_ppa git-core/ppa

    sudo apt-get install -y git

    if [ ! -d "$HOME/aws-config" ]; then
        git clone git://github.com/Khan/aws-config "$HOME/aws-config"
    fi
    ( cd "$HOME/aws-config" && git pull && git submodule update --init --recursive )
}

install_basic_packages() {
    # To make life easier, let's set up our hostname first.
    ec2_hostname=`basename "$CONFIG_DIR"`
    echo "$ec2_hostname" | sudo tee /etc/hostname
    if ! grep -q "$ec2_hostname" /etc/hosts; then
        echo "127.0.0.1 $ec2_hostname" | sudo tee -a /etc/hosts
    fi
    sudo hostname `cat /etc/hostname`

    echo "Installing packages: Basic setup"
    sudo apt-get install -y git
    sudo apt-get install -y python-pip
    sudo apt-get install -y python-dbg gdb   # lets us debug python via gdb
    sudo apt-get install -y ntp
    sudo apt-get install -y aptitude  # used by our cron.daily script

    # Not needed, but useful
    sudo apt-get install -y curl

    # This is needed so installing postfix doesn't prompt.  See
    # http://www.ossramblings.com/preseed_your_apt_get_for_unattended_installs
    # If it prompts anyway, type in the stuff from postfix.preseed manually.
    echo "postfix postfix/mailname string `hostname`.khanacademy.org" > /tmp/postfix.preseed
    echo "postfix postfix/main_mailer_type select Internet Site" >> /tmp/postfix.preseed
    sudo apt-get install -y debconf-utils
    sudo debconf-set-selections /tmp/postfix.preseed
    sudo apt-get install -y postfix

    echo "(Finishing up postfix config)"
    sudo sed -i -e 's/myorigin = .*/myorigin = khanacademy.org/' \
                -e 's/myhostname = .*/myhostname = '"`hostname`"'.khanacademy.org/' \
                -e 's/inet_interfaces = all/inet_interfaces = loopback-only/' \
                /etc/postfix/main.cf

    # Make sure mail to root is sent to us admins.
    if ! grep -q "root:" /etc/postfix/canonical 2>/dev/null; then
        mailto="`hostname`-admin+${mailsuffix-root}@khanacademy.org"
        echo "root $mailto" | sudo tee -a /etc/postfix/canonical
        # For some reason sometimes I need this name as well.
        echo "root@`hostname` $mailto" | sudo tee -a /etc/postfix/canonical
        sudo postmap /etc/postfix/canonical

        # Make sure we know to look in at this file we just wrote.
        if ! grep -q /etc/postfix/canonical /etc/postfix/main.cf; then
            echo "canonical_maps = hash:/etc/postfix/canonical" | sudo tee -a /etc/postfix/main.cf
        fi

        echo "Cron is set up to send mail to `hostname`-admin@ka.org."
        echo "Make sure that group exists (or else create it) at"
        echo "https://groups.google.com/a/khanacademy.org/forum/#!myforums"
        echo "Hit <enter> when this is done:"
        read prompt
    fi

    sudo service postfix restart

    # Set the timezone to PST/PDT.  The 'tee' trick writes via sudo.
    echo "America/Los_Angeles" | sudo tee /etc/timezone
    sudo dpkg-reconfigure -f noninteractive tzdata

    # Restart cron to pick up the new timezeone.
    sudo service cron restart
}

setup_logs_dir() {
    # By default, we put logs on an ephemeral disk if possible.
    if [ ! -d "$HOME/logs" ]; then
        echo "Making a logs directory to store logs (and symlinks to logs)"
        rm -f "$HOME/logs"            # just in case it's a file or something
        if [ -d "/mnt" ]; then        # this is the ephemeral disk
            sudo mkdir -p /mnt/logs
            ln -snf /mnt/logs "$HOME/logs"
        else
            mkdir "$HOME/logs"
        fi
        sudo chmod 1777 "$HOME/logs"
    fi
}

# $1: the root where you'll be copying files from (eg $CONFIG_DIR)
# $2: a list of filenames to exclude from installing (e.g. "/etc/rc.local")
_install_root_config_files() {
    echo "Updating config files on the root filesystem (using symlinks to $1)"
    ROOT="$1"
    excludes=" $2 "

    if [ -d "$ROOT"/etc ]; then
        find "$ROOT"/etc ! -type d -print | while read etcfile; do
            dest=`_to_fs "$etcfile" "$ROOT"`
            # If the user doesn't want to install this file, respect that
            echo "$excludes" | grep -q " $dest " && continue
            sudo ln -snfv --backup=numbered "$etcfile" "$dest"
        done
        sudo chown root:root /etc
    fi
    # Make sure that we've added the info we need to the fstab.
    # ('tee -a' is the way to do '>>' that works with sudo.)
    if [ -s /etc/fstab.extra ]; then
        grep -xqf /etc/fstab.extra /etc/fstab || \
            cat /etc/fstab.extra | sudo tee -a /etc/fstab >/dev/null

        # Make sure all the disks in the fstab are mounted.
        sudo mount -a
    fi

    # Stuff in /etc/init needs to be owned by root, so we copy instead of
    # symlinking there.
    if [ -d "$ROOT/etc/init" ]; then
        # We also add a symlink to these guys' logs in our own logs dir.
        setup_logs_dir
        for initfile in "$ROOT"/etc/init/*; do
            dest=`_to_fs "$initfile" "$ROOT"`
            # If the user doesn't want to install this file, respect that
            echo "$excludes" | grep -q " $dest " && continue
            sudo rm -f "$dest"
            sudo install -m644 "$initfile" "$dest"
            ln -snf /var/log/upstart/"`basename "$initfile" .conf`".log "$HOME"/logs/
        done
    fi
    # Same for stuff in /etc/cron.*
    if [ -n "`ls "$ROOT"/etc/cron.*`" ]; then
        for cronfile in "$ROOT"/etc/cron.*/*; do
            dest=`_to_fs "$cronfile" "$ROOT"`
            echo "$excludes" | grep -q " $dest " && continue
            sudo rm -f "$dest"
            sudo install -m755 "$cronfile" "$dest"
        done
    fi
}


install_root_config_files() {
    _install_root_config_files "$CONFIG_DIR" ""
    # We also install all the shared files from ../shared/.
    # SHARED_EXCLUDE_FILES is (optionally) defined in a config-dir's setup.sh
    _install_root_config_files "`dirname $CONFIG_DIR`/shared" "$SHARED_FILE_EXCLUDES"
}

install_user_config_files() {
    echo "Updating dotfiles (using symlinks)"
    if [ -n "`ls "$CONFIG_DIR/.[!.]*"`" ]; then
        for dotfile in "$CONFIG_DIR"/.[!.]*; do
            ln -snfv "$dotfile"
        done
    fi
    setup_logs_dir
}

install_npm() {
    # see https://github.com/joyent/node/wiki/Installing-Node.js-via-package-manager
    add_ppa chris-lea/node.js        # in setup_fns.sh
    sudo apt-get install -y nodejs
}

install_build_deps() {
    # Note this just installs the system deps.  You still need to
    # check out the webapp repo yourself, then run 'make deps' to
    # install the next (application) layer of deps.
    echo "Installing system deps needed to 'make build'/'make check' in webapp"

    sudo apt-get install -y g++ make

    # Python deps
    sudo apt-get install -y python-dev  # for numpy
    sudo apt-get install -y python-software-properties python
    sudo pip install virtualenv

    # Node deps
    install_npm

    # Ruby deps
    sudo apt-get install -y ruby rubygems
    sudo REALLY_GEM_UPDATE_SYSTEM=1 gem update --system
    sudo apt-get install -y ruby1.8-dev ruby1.8 ri1.8 rdoc1.8 irb1.8
    sudo apt-get install -y libreadline-ruby1.8 libruby1.8 libopenssl-ruby
    # nokogiri requirements (gem install does not suffice on Ubuntu)
    # See http://nokogiri.org/tutorials/installing_nokogiri.html
    sudo apt-get install -y libxslt-dev libxml2-dev
    sudo gem install bundler

    # jstest deps
    if ! which phantomjs >/dev/null; then
        (
            cd /usr/local/share
            case `uname -m` in
                i?86) mach=i686;;
                *) mach=x86_64;;
            esac
            sudo rm -rf phantomjs
            wget "https://phantomjs.googlecode.com/files/phantomjs-1.9.2-linux-${mach}.tar.bz2" -O- | sudo tar xfj -

            sudo ln -snf /usr/local/share/phantomjs-1.9.2-linux-${mach}/bin/phantomjs /usr/local/bin/phantomjs
        )
        which phantomjs >/dev/null
    fi

    # Some KA tests write to /tmp and don't clean up after themselves,
    # on purpose (see kake/server_client.py:rebuild_if_needed().  We
    # install tmpreaper to clean up those files "eventually".
    # This avoids prompting at install time.
    sudo apt-get install -y debconf-utils
    echo "tmpreaper tmpreaper/readsecurity note" | sudo debconf-set-selections
    echo "tmpreaper tmpreaper/readsecurity_upgrading note" | sudo debconf-set-selections
    sudo apt-get install -y tmpreaper
    # We need to comment out a line before tmpreaper will actually run.
    sudo perl -pli -e s/^SHOWWARNING/#SHOWWARNING/ /etc/tmpreaper.conf
}

# Needed for ec2-api-tools
activate_multiverse() {
    sudo perl -pi~ -e 'next if /-backports/; s/^# (deb .* multiverse)$/$1/' \
        /etc/apt/sources.list
    sudo apt-get update
}

# Decrypt a secrets file whose encrypted form lives in the aws-config repo.
# The main argument is the password to use for decryption.
# $1: Decrypted secret filename (should be an absolute filename)
# $2: Encrypted secret filename, should end in .cast5 (absolute filename)
# $3: The phabricator passphrase url where the password is stored, e.g. "K5"
decrypt_secret() {
    decrypted_name="`echo "$2" | sed 's/\.cast5$//'`"
    if [ "$decrypted_name" = "$2" ]; then
        echo "Second argument to install_secret ($2) must end in '.cast5'."
        exit 1
    fi
    if [ ! -s "$1" ]; then
        echo "-- You need to decrypt the secrets at $1."
        echo "-- To do this, enter the password from https://phabricator.khanacademy.org/$3"
        make -f "$CONFIG_DIR/Makefile" "$decrypted_name"
        # If "$1" is someplace like /etc, we'll retry as root.
        mkdir -p "`dirname "$1"`" || sudo mkdir -p "`dirname "$1"`"
        install -m 600 "$decrypted_name" "$1" || \
            sudo install -m 600 "$decrypted_name" "$1"
        rm -f "$decrypted_name"
    fi
}

# Have the user install a secret that lives on phabricator.  The main
# argument is the url of that secret.
# $1: secret filename (should be an absolute filename)
# $2: The phabricator passphrase url where this secret is stored (e.g. "K5")
install_secret() {
    if [ ! -s "$1" ]; then
        echo "You need to install a secret into $1."
        echo "To do this, cut and paste the secret from"
        echo "   https://phabricator.khanacademy.org/$2"
        read -p "Paste the secret here: " prompt
        mkdir -p "`dirname "$1"`"
        # If "$1" is someplace like /etc, we'll retry as root.
        echo "$prompt" | tee -a "$1" >/dev/null \
            || echo "$prompt" | sudo tee -a "$1" >/dev/null
        sudo chmod 600 "$1"
    fi
}

# Have the user install a secret that lives on phabricator.  The main
# argument is the url of that secret.
# $1: secret filename (should be an absolute filename)
# $2: The phabricator file url where this secret is stored (e.g. "F1234")
install_multiline_secret() {
    if [ ! -s "$1" ]; then
        echo "You need to install a secret into $1."
        echo "To do this, cut and paste the secret from"
        echo "   https://phabricator.khanacademy.org/$2"
        echo "Paste the secret contents here, then hit control-D:"
        prompt=`cat`

        mkdir -p "`dirname "$1"`"
        # If "$1" is someplace like /etc, we'll retry as root.
        echo "$prompt" | tee -a "$1" >/dev/null \
            || echo "$prompt" | sudo tee -a "$1" >/dev/null
        sudo chmod 600 "$1"
    fi
}

# Have the user enter a secret from secrets.py, which we will save
# in a local file.
# $1: secret filename (should be an absolute filename)
# $2: The name of the variable in webapp's secrets.py.
# $3: If specified and is "python", emit the secret as a python line
#     (e.g. 'mysecret = "secret-value"'.)  The secret must not contain
#     single-quotes or double-quotes.
install_secret_from_secrets_py() {
    if [ "$3" = "python" ]; then
        if [ ! -s "$1" ] || ! grep -q "^$2 = " "$1"; then
            echo "You need to install a secret into $1."
            echo "To do this, cut and paste the value of '$2'"
            echo "from webapp's secrets.py."
            read -p "Paste the secret here: " prompt
            prompt="$2 = "\""$prompt"\"
        fi
    else
        if [ ! -s "$1" ]; then
            echo "You need to install a secret into $1."
            echo "To do this, cut and paste the value of '$2'"
            echo "from webapp's secrets.py."
            read -p "Paste the secret here: " prompt
        fi
    fi
    if [ -n "$prompt" ]; then
        mkdir -p "`dirname "$1"`"
        # If "$1" is someplace like /etc, we'll retry as root.
        echo "$prompt" | tee -a "$1" >/dev/null \
            || echo "$prompt" | sudo tee -a "$1" >/dev/null
        sudo chmod 600 "$1"
    fi
}

install_alertlib_secret() {
    install_secret_from_secrets_py "$HOME/alertlib_secret/secrets.py" hipchat_alertlib_token python
    install_secret_from_secrets_py "$HOME/alertlib_secret/secrets.py" hostedgraphite_api_key python
}

install_varnish() {
    if [ -d "$CONFIG_DIR"/etc/varnish ]; then
        if [ ! -d /etc/varnish ]; then
            install_root_config_files     # copy from our etc/varnish
        fi
        echo "Installing varnish"
        sudo apt-get install -y varnish
        sudo /etc/init.d/varnish restart
    fi
}

install_nginx() {
    if [ -n "`ls "$CONFIG_DIR"/nginx_site_*`" ]; then
        echo "Installing nginx"
        # Sometimes we need a more modern nginx than ubuntu 12.04 provides.
        add_ppa nginx/stable
        sudo apt-get install -y nginx

        # Make sure there's a logs directory.
        setup_logs_dir

        sudo rm -f /etc/nginx/sites-enabled/default
        for f in "${CONFIG_DIR}"/nginx_site_*; do
            site_name="`basename $f | sed s/nginx_site_//`"
            sudo ln -sfnv "$f" "/etc/nginx/sites-available/$site_name"
            sudo ln -sfnv "/etc/nginx/sites-available/$site_name" "/etc/nginx/sites-enabled/$site_name"

            # Make sure that the server that we're using actually
            # resolve.
            nginx_hostname=`sed -n 's/^ *server_name //p' "$f" | tr -d ';'`
            if [ -n "$nginx_hostname" ]; then
                host "$nginx_hostname" >/dev/null 2>&1 || {
                    echo "$f listens on $nginx_hostname but that host does not resolve."
                    echo "You should set it up as an A or CNAME on ec2."
                    echo "Hit <enter> to continue"
                    read prompt
                }
            fi

            # Make sure that we log to our logs directory.
            grep -q "access_log.* $HOME/logs/${site_name}-access.log" "$f" || {
                echo "You must set an access_log directive in $f"
                echo "that points to $HOME/logs/${site_name}-access.log"
                echo "Fix $f and re-run setup.sh"
                exit 1
            }
            grep -q "error_log.* $HOME/logs/${site_name}-error.log" "$f" || {
                echo "You must set an error_log directive in $f"
                echo "that points to $HOME/logs/${site_name}-error.log"
                echo "Fix $f and re-run setup.sh"
                exit 1
            }
        done

        # Make sure there's a logrotate script for the nginx logs,
        # now that they're in a custom location.  We just copy
        # the nginx one and modify it.  Main thing is we keep only
        # a month's worth of logs, rather than a year.
        sed \
            -e "s@/var/log/nginx/\*.log@$HOME/logs/*-access.log $HOME/logs/*-error.log@" \
            -e "s@rotate .*@rotate 4@" \
            /etc/logrotate.d/nginx | sudo sh -c 'cat > /etc/logrotate.d/nginx_local'

        sudo service nginx restart

        # Finally, give nginx permission to see stuff in our repos.
        # Our umask is all right, the only problem is the default
        # permission on our homedir itself.
        chmod a+rX "$HOME"
    fi
}


install_crontab() {
    if [ -s "$CONFIG_DIR/crontab" ]; then
        echo "Installing the crontab"
        crontab "$CONFIG_DIR/crontab"
    fi
}

start_daemons() {
    if [ -d "$CONFIG_DIR/etc/init" ]; then
        echo "Starting daemons in $CONFIG_DIR/etc/init"
        for daemon in "$CONFIG_DIR"/etc/init/*.conf; do
            sudo stop `basename $daemon .conf` || true
            sudo start `basename $daemon .conf`
        done
    fi
}
