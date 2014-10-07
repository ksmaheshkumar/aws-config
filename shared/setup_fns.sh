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

# $1: an absolute file like $CONFIG_DIR/etc/foo.  Returns /etc/foo.
_to_fs() {
   echo "$1" | sed "s,^$CONFIG_DIR,,"
}


# $1: name of the ppa, eg. "chris-lea/node.js"
add_ppa() {
    if ! ls /etc/apt/sources.list.d/ 2>&1 | grep -q `echo $1 | tr / .`; then
        sudo add-apt-repository -y ppa:"$1"
    fi
    sudo apt-get update
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
    echo "Installing packages: Basic setup"
    sudo apt-get install -y git
    sudo apt-get install -y python-pip
    sudo apt-get install -y python-dbg gdb   # lets us debug python via gdb
    sudo apt-get install -y ntp
    sudo apt-get install -y aptitude  # used by our cron.daily script

    # This is needed so installing postfix doesn't prompt.  See
    # http://www.ossramblings.com/preseed_your_apt_get_for_unattended_installs
    # If it prompts anyway, type in the stuff from postfix.preseed manually.
    if [ -s "$CONFIG_DIR"/postfix.preseed ]; then
        sudo apt-get install -y debconf-utils
        sudo debconf-set-selections "$CONFIG_DIR"/postfix.preseed
        sudo apt-get install -y postfix

        echo "(Finishing up postfix config)"
        hostname=`env LC_ALL=C grep -o '[!-~]*.khanacademy.org' "$CONFIG_DIR"/postfix.preseed`
        sudo sed -i -e 's/myorigin = .*/myorigin = khanacademy.org/' \
                    -e 's/myhostname = .*/myhostname = '"$hostname"'/' \
                    -e 's/inet_interfaces = all/inet_interfaces = loopback-only/' \
                    /etc/postfix/main.cf
        sudo service postfix restart
    fi

    # Set the timezone to PST/PDT.  The 'tee' trick writes via sudo.
    echo "America/Los_Angeles" | sudo tee /etc/timezone
    sudo dpkg-reconfigure -f noninteractive tzdata

    # Let's make sure we have a reasonable hostname!
    sudo hostname "`basename "$CONFIG_DIR"`"

    # Not needed, but useful
    sudo apt-get install -y curl
}

install_root_config_files() {
    echo "Updating config files on the root filesystem (using symlinks)"

    if [ -d "$CONFIG_DIR"/etc ]; then
        sudo cp -sav --backup=numbered "$CONFIG_DIR"/etc/ /
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
    if [ -d "$CONFIG_DIR/etc/init" ]; then
        for initfile in "$CONFIG_DIR"/etc/init/*; do
            rm -f "`_to_fs "$initfile"`"
            sudo install -m644 "$initfile" "`_to_fs "$initfile"`"
        done
    fi
    # Same for stuff in /etc/cron.*
    if [ -n "`ls "$CONFIG_DIR"/etc/cron.*`" ]; then
        for cronfile in "$CONFIG_DIR"/etc/cron.*/*; do
            rm -f "`_to_fs "$cronfile"`"
            sudo install -m755 "$cronfile" "`_to_fs "$cronfile"`"
        done
    fi
}

install_user_config_files() {
    echo "Updating dotfiles (using symlinks)"
    if [ -n "`ls "$CONFIG_DIR/.[!.]*"`" ]; then
        for dotfile in "$CONFIG_DIR"/.[!.]*; do
            ln -snfv "$dotfile"
        done
    fi
}

# Needed for ec2-api-tools
activate_multiverse() {
    sudo perl -pi~ -e 'next if /-backports/; s/^# (deb .* multiverse)$/$1/' \
        /etc/apt/sources.list
}

install_alertlib_secret() {
    if [ ! -s "$HOME/alertlib_secret/secrets.py" ]; then
        echo "Run:"
        echo "---"
        echo "mkdir -p ~/alertlib_secret"
        echo "chmod 700 ~/alertlib_secret"
        echo "cat <<EOF > ~/alertlib_secret/secrets.py"
        echo 'hipchat_alertlib_token = "<value>"'
        echo 'hostedgraphite_api_key = "<value>"'
        echo 'EOF'
        echo "---"
        echo "where these lines are taken from secrets.py."
        echo "Hit <enter> when this is done:"
        read prompt
    fi
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
        sudo rm -f /etc/nginx/sites-enabled/default
        for f in "${CONFIG_DIR}"/nginx_site_*; do
            site_name="`basename $f | sed s/nginx_site_//`"
            sudo ln -sfnv "$f" "/etc/nginx/sites-available/$site_name"
            sudo ln -sfnv "/etc/nginx/sites-available/$site_name" "/etc/nginx/sites-enabled/$site_name"
        done
        sudo service nginx restart
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
