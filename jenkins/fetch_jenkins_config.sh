#!/bin/sh -e

# Fetch a subset of configuration from a remote Jenkins server, by default the
# server is ka-jenkins.
#
# The motivation is that Jenkins tends to be configured via the web UI and
# persists its own config into XML, XML that we want in source control to more
# easily configure a new Jenkins instance. This script is meant to be run from
# a local checkout of a source repository on a development machine and modifies
# local files under ./jenkins_home/ to match the remote server's configuration.
#
# This works by gathering all the paths rooted in the local jenkins_home/
# directory and using rsync over SSH to copy the corresponding files rooted at
# the $HOME of the jenkins user on the ka-jenkins server.
#
# USAGE:
#   $ ./fetch_jenkins_config.sh
#   receiving file list ... done
#   jobs/website-commit/config.xml
#   ...
#
# To fetch a new file first create the local file then run the fetch script:
#   $ touch jenkins_home/jobs/a-new-job/config.xml

# TODO(chris): detect missing files that should be copied.

# Make sure we're in the directory this script resides in.
cd "`dirname $0`/jenkins_home"

host=ka-jenkins
remote_jenkins_home=/var/lib/jenkins

find . -type f -print0 \
  | rsync -av -e ssh --rsync-path="sudo -u jenkins rsync" --files-from=- --from0 "$host":"$remote_jenkins_home" .
