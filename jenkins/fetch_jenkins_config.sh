#!/bin/sh -e

# Fetch XML configuration from a remote Jenkins server, by default the server
# is ka-jenkins.
#
# Jenkins is configured via the web UI and persists config into XML that we
# want under source control. This script is meant to be run from a local
# checkout of a source repository on a development machine and modifies local
# files under ./jenkins_home/ to match the remote server's configuration.
#
# USAGE:
#   $ ./fetch_jenkins_config.sh
#   receiving file list ... done
#   jobs/website-commit/config.xml
#   ...

# Make sure we're in the directory this script resides in.
cd "`dirname $0`/jenkins_home"

host=ka-jenkins
remote_jenkins_home=/var/lib/jenkins

# The include/exclude filters are non-obvious. See "FILTER RULES" in "man
# rsync". Each filter is applied in order at each level of a recursive descent.
# The idea is to sync all XML configuration in the home directory and jobs/*/
# but to exclude files that we list in fetch_jenkins_config.exclude
rsync -avk -e ssh --rsync-path="sudo -u jenkins rsync" \
  --exclude-from=../fetch_jenkins_config.exclude \
  --include='/jobs' --include='/jobs/*' --include='/jobs/*/*.xml' \
  --include='/*.xml' \
  --exclude='*' \
  "$host":"$remote_jenkins_home"/ .
