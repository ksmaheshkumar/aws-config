#!/usr/bin/env python

"""Create a snapshot of a given ec2 EBS volume, deleting old snapshots.

You specify how many snapshots to keep.  By default, this keeps the
most recent n/2 daily snapshots, the most recent n/4 weekly snapshots,
and the most recent n/4 monthly snapshots.

NOTE: the ec2-* binaries must be on the path!
TODO(csilvers): use http://docs.pythonboto.org instead

Inspired by http://www.geekytidbits.com/rolling-snapshots-ec2/.
"""


import datetime
import subprocess


def all_snapshots(volume, description, ec2_arglist, today, dry_run):
    """(snapshot-id, date) of all snapshots of volume matching description."""
    if dry_run:
        # We have to yield the one we pretended we made today.
        yield ('snapshot-TBD', today.strftime('%Y-%m-%d:%H:%M%:S+0000'))

    output = subprocess.check_output(['ec2-describe-snapshots', '--hide-tags']
                                     + ec2_arglist)
    for line in output.splitlines():
        (unused_type, snapshot_id, volume_id, status, date,
         unused_pct, unused_owner_id, unused_volume_size,
         snapshot_description) = line.split('\t')
        if volume_id == volume and snapshot_description == description:
            yield (snapshot_id, date)


def create_snapshot(volume, description, freezedir, ec2_arglist, dry_run):
    if dry_run:
        print '[DRY RUN] Created snap-TBD for %s' % volume
        return

    # At the very least, sync to try to make the disk consistent.
    subprocess.call(['/bin/sync'])    # best-effort
    if freezedir:
        subprocess.check_call(['sudo', '/sbin/fsfreeze', '-f', freezedir])

    try:
        output = subprocess.check_output(['ec2-create-snapshot',
                                          '-d', description]
                                         + ec2_arglist + [volume])
        # Output is, e.g.
        # SNAPSHOT\tsnap-e1cc35a1\tvol-06f30e77\tpending\t\
        #    2013-02-05T00:08:06+0000759597320137\t100\ttest snapshot
        if output.split('\t')[3] not in ('pending', 'completed'):
            raise RuntimeError('Snapshot state not pending or completed: "%s"'
                               % output)
        print 'Created %s from %s' % (output.split('\t')[1], volume)
    finally:
        if freezedir:
            subprocess.check_call(['sudo', '/sbin/fsfreeze', '-u', freezedir])


def delete_snapshot(snapshot_id, snapshot_date, ec2_arglist, dry_run):
    if dry_run:
        print '[DRY RUN] Deleting %s (%s)' % (snapshot_id, snapshot_date)
        return

    output = subprocess.check_output(['ec2-delete-snapshot']
                                     + ec2_arglist + [snapshot_id])
    # Output is, e.g.
    # SNAPSHOT\tsnap-e1cc35a1
    if output != 'SNAPSHOT\t%s' % snapshot_id:
        raise RuntimeError('Unexpected output from ec2-delete-snapshot: "%s"'
                           % output)
    print 'Deleted %s (%s)' % (snapshot_id, snapshot_date)


def calculate_good_snapshots(num_daily, num_weekly, num_monthly, today):
    """Calculate the date-prefix for snapshots we should keep.

    Arguments:
       num_daily: number of daily snapshots we should keep (including today)
       num_weekly: number of weekly snapshots we should keep
       num_monthly: number of monthly snapshots we should keep
       today: today, as a datetime.date, in UTC timezone.

    Returns:
       A set of datetime.date objects: all snapshots created on those
       days we should keep.  The rule is we keep the last D daily
       snapshots, the last W Sunday snapshots, and the last M
       1st-of-month snapshots, starting counting with today's
       snapshot.
    """
    keep = set()
    for i in xrange(num_daily):
        day = today - datetime.timedelta(i)
        keep.add(day)

    # Sunday has weekday 6, so this gets us to the previous sunday.
    last_sunday = today - datetime.timedelta((today.weekday() + 1) % 7)
    for i in xrange(num_weekly):
        day = last_sunday - datetime.timedelta(i * 7)
        keep.add(day)

    last_first_of_month = [today.year, today.month, 1]
    for i in xrange(num_monthly):
        day = datetime.date(*last_first_of_month)
        keep.add(day)
        last_first_of_month[1] -= 1
        if last_first_of_month[1] == 0:
            last_first_of_month[0] -= 1
            last_first_of_month[1] += 12

    return keep


def delete_old_snapshots(all_snapshots,
                         num_daily, num_weekly, num_monthly, today,
                         ec2_arglist, dry_run):
    """all_snapshots is a list of (snapshot_id, snapshot_date) pairs."""
    to_keep = calculate_good_snapshots(num_daily, num_weekly, num_monthly,
                                       today)
    for (snapshot_id, snapshot_date) in all_snapshots:
        # date is in format 'YYYY-MM-DDTHH:MM:SS+TTZZ'
        snapshot_dt = datetime.date(int(snapshot_date[0:4]),
                                    int(snapshot_date[5:7]),
                                    int(snapshot_date[8:10]))
        if snapshot_dt not in to_keep:
            delete_snapshot(snapshot_id, snapshot_date, ec2_arglist, dry_run)


def main(volume, description, max_snapshots,
         num_daily, num_weekly, num_monthly, freezedir, ec2_arglist, dry_run,
         today=datetime.date.today()):
    """Delete 'old' snapshots matching 'description' on the given volume.

    NOTE: the ec2-* binaries must be on $PATH!

    Arguments:
        volume: the ec2 EBS volume to snapshot.
        description: used as the snapshot description.  All snapshots
          sharing the same description are part of a 'snapshot series'.
        max_snapshots: do not keep more than this many snapshots in
          one snapshot series.
        num_daily: how many daily snapshots to keep.  If None, make it
          max_snapshots - num_weekly - num_monthly.
        num_weekly: how many weekly snapshots to keep.  If None, make it
          max_snapshots / 4
        num_monthly: how many monthly snapshots to keep.  If None, make it
          max_snapshots / 4
        freezedir: if not None, call fsfreeze on this directory while
          snapshotting.  This causes the disk to be frozen for writes,
          yielding a more-likely-consistent snapshot.
        ec2_arglist: a list like ['-K', 'foo', '-C', 'foo'].  It is passed
          directly to the ec2 snapshot commands.
        dry_run: if True, just say what we'd do, but don't do it.
        today: the day we start calculating snapshots to keep, from.
          It should be a datetime.date() object in UTC.
    """
    snapshots = list(all_snapshots(volume, description, ec2_arglist, today,
                                   dry_run))

    if num_weekly is None:
        num_weekly = max_snapshots / 4
    if num_monthly is None:
        num_monthly = max_snapshots / 4
    if num_daily is None:
        num_daily = max_snapshots - num_weekly - num_monthly
    if num_daily < 1:
        raise ValueError('Must keep at least one daily snapshot!'
                         '  (daily=%s, weekly=%s, monthly=%s)'
                         % (num_daily, num_weekly, num_monthly))

    create_snapshot(volume, description, freezedir, ec2_arglist, dry_run)
    delete_old_snapshots(snapshots, num_daily, num_weekly, num_monthly, today,
                         ec2_arglist, dry_run)


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(
        description='Create a new snapshot and delete too-old snapshots.')
    parser.add_argument('--description', '-d', required=True,
                        help=('Identify related snapshots (related == share'
                              ' a description).  Passed to ec2.'))
    parser.add_argument('--dry_run', '-n', action='store_true',
                        help='Say what we would do without doing it')
    parser.add_argument('--volume', '-v', required=True,
                        help='volume-id of the EBS volume to snapshot')
    parser.add_argument('--max_snapshots', '-m', type=int,
                        required=True,
                        help='The number of snapshots to keep')
    parser.add_argument('--max-weekly-snapshots', type=int,
                        help=('How many weekly snapshots to take.  Must be'
                              ' less than --max_snapshots.  Default is'
                              ' max_snapshots / 4'))
    parser.add_argument('--max-monthly-snapshots', type=int,
                        help=('How many monthly snapshots to take.  Must be'
                              ' less than --max_snapshots.  Default is'
                              ' max_snapshots / 4'))
    parser.add_argument('--freezedir',
                        help=('If specified, call /sbin/fsfreeze on this'
                              ' volume while snapshotting it.  You must'
                              ' be able to sudo to root to use this.'))
    # max_daily_snapshots is always max_snapshots - weekly - monthly.
    ec2_args = ('-K', '-C', '-U', '--region')
    for ec2_arg in ec2_args:
        parser.add_argument(ec2_arg, help='Passed directly to ec2 commands')

    args = parser.parse_args()
    ec2_arglist = []
    for a in ec2_args:
        a_varname = a.lstrip('-').replace('-', '_')
        if getattr(args, a_varname, None) is not None:
            ec2_arglist.append(a)                          # e.g. '--region'
            ec2_arglist.append(getattr(args, a_varname))   # e.g. 'us-east1'

    main(args.volume, args.description, args.max_snapshots,
         None, args.max_weekly_snapshots, args.max_monthly_snapshots,
         args.freezedir, ec2_arglist, args.dry_run)
