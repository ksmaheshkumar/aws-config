#!/bin/bash

# For use on a freshly-booted Ubuntu 11.10 AMI to create a role account with
# sudo access, as well as move the ssh authorized_keys file from "ubuntu" which
# essentially disables the "ubuntu" account.

# Run me as:
#     ./create_role_account.sh USERNAME | ssh -i KEYFILE ubuntu@IP_ADDRESS sh

# Not idempotent.


ROLE=$1

if [ -z "$ROLE" ]; then
  echo "Usage: ./create_role_account.sh USERNAME"
  exit 1
fi

# Add the user account
echo sudo adduser --disabled-password $ROLE --gecos \"\"

# mkdir .ssh
echo sudo -u $ROLE mkdir -p ~$ROLE/.ssh/

# Move .ssh/authorized_keys over
echo sudo mv ~ubuntu/.ssh/authorized_keys ~$ROLE/.ssh/
echo sudo chown -R $ROLE: ~$ROLE/.ssh/
echo sudo chmod 600 ~$ROLE/.ssh/authorized_keys

# Add role account to sudoers
echo echo "\"$ROLE ALL=(ALL) NOPASSWD:ALL\"" \| \
  sudo tee -a /etc/sudoers.d/90-cloudimg-ubuntu \>/dev/null
