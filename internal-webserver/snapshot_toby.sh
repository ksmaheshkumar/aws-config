#!/bin/sh

# A script that makes a (rolling) snapshot of the data on toby.
#
# This assumes that the volume holding toby's data has a tag named
# 'Name' with value 'toby data ...'  And that this volume is an XFS
# volume.

set -e       # die if any command fails

VOLUME=`ec2-describe-volumes \
        -K ~/aws/pk-backup-role-account.pem \
        -C ~/aws/cert-backup-role-account.pem \
        | grep -e 'TAG.*toby data' \
        | cut -f3`
if [ `echo "$VOLUME" | wc -l` -ne 1 ]; then
  echo "Cannot find a unique volume tagged with the name 'toby data'."
  exit 1
fi

PATH="$PATH":/usr/bin       # for ec2-*.

"$HOME/aws-config/aws-tools/ec2-create-rolling-snapshot.py" \
    -m 16 \
    -d 'backup of toby data' \
    -v "$VOLUME" \
    --freezedir=/opt \
    -K ~/aws/pk-backup-role-account.pem \
    -C ~/aws/cert-backup-role-account.pem


