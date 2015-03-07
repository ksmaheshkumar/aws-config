#!/bin/sh -e

# This updates a Jenkins slave machine.
#
# Jenkins starts up slave machines automatically, when needed, by
# starting a new ec2 instance using an AMI that we provide.  You can
# (should) update the slave AMI every few months to include the latest
# git revisions.  This makes starting up a new slave faster since it
# doesn't need to fetch as much from git.  This script helps with that.
#
# You should run it on a jenkins slave-like machine (that is, either
# a jenkins slave machine or one that was started using the same AMI;
# a good way to get the latter is to go to the ec2 console, select an
# existing jenkins slave machine, and run 'Launch more like this').

# $1: directory to update
git_update() {
    (
    cd $1
    git pull
    git submodule sync
    git submodule update --init --recursive
    )
}

git_update /var/lib/jenkins/repositories/webapp
git_update ~/webapp-workspace/jenkins-tools
git_update ~/webapp-workspace/webapp

instance_id=`curl http://169.254.169.254/latest/meta-data/instance-id`

# TODO(csilvers): automate the AMI-creation part of this (but not sure
# I can do that from the ec2-slave machine itself?)

cat<<EOF
Next steps:

1) Log into the aws console and go to
   https://console.aws.amazon.com/ec2/v2/home?region=us-east-1#Instances

2) Click on the entry for this machine (instance-ID $instance_id)

3) From the 'Actions' menu at the top, select "Image -> Create Image"

4) Name the image: jenkins-slave-`date +%Y%m%d`

5) Click "Create Image".  The resulting pop-up will say:
   "View pending image ami-XXXXXXXX".  Record (cut-and-paste) that ami-ID.
   Heck, click on the link to go to the AMI page.
[you may want to wait for the AMI to finish building before continuing]

6) Visit http://jenkins.khanacademy.org/configure

7) Search for "AMI ID" (in the "Cloud" section)

8) Copy the ami-ID from step 5 (including the "ami-" prefix) here.

9) Click "Check AMI" to make sure all is good.  Then click "Save"

10) Once the AMI is finished building, terminate the ec2 instance you
    used for this, if you created a new one just for this purpose.

11) [optional] Go to the ec2 instances page, select all existing jenkins
    slave instances, and terminate them.  This will force the next
    deploy to use the new ami, allowing you to test everything!
EOF
