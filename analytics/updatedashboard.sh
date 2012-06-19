#!/bin/sh

# Updates the dashboards webapp on the machine.
# Can be run either directly on the machine, or by running
#
# $ cat updatedashboard.sh | ssh analytics sh
#

cd $HOME/analytics
git pull
sudo service dashboards-daemon restart

