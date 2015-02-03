# NOTE: make sure the google group is set up to have root@khanacademy.org
#       as a member, or this mail will bounce!
# 'hostname' should be 'basename `cat /etc/mailname` .khanacademy.org'
MAILTO = {{hostname}}-admin+crontab@khanacademy.org
PATH = /usr/local/bin:/usr/bin:/bin

# Every minute, check if we had an OOM event, and if so send mail.
# (We 'send mail' by echoing the output, which MAILTO above turns into
# mail.)  The OOM message in kern.log starts with '<something> invoked
# oom-killer' and ends with 'Killed process <something>'.  This will
# print all OOM messages in the logfile, even rather old ones.
# TODO(csilvers): only print OOM's that ended within the last minute.
* * * * *       root    find /var/log -name 'kern.log.*' -mmin -2 -print0 | xargs -0 -r sed -ne '/invoked oom-killer/,/Killed process/p'
