#!/bin/sh
# Fixed staging account only. PHP never launches processes; this wrapper owns cron CLI.
set -eu
umask 077
jivie_upgrade_work='/home/tripar13/private/jivie-test/upgrade-0.11.0'
jivie_upgrade_php='/opt/alt/php84/usr/bin/php'
jivie_upgrade_helper="$jivie_upgrade_work/upgrade-cpanel-jivie-sharing.php"
jivie_upgrade_crontab='/bin/crontab'
case "${1-}" in
  prepare)
    test -d "$jivie_upgrade_work"
    test ! -e "$jivie_upgrade_work/crontab.original"
    "$jivie_upgrade_crontab" -l > "$jivie_upgrade_work/crontab.original"
    chmod 600 "$jivie_upgrade_work/crontab.original"
    "$jivie_upgrade_php" -l "$jivie_upgrade_helper"
    "$jivie_upgrade_php" "$jivie_upgrade_helper" --check
    "$jivie_upgrade_php" "$jivie_upgrade_helper" --prepare
    ;;
  pause)
    "$jivie_upgrade_crontab" -l > "$jivie_upgrade_work/crontab.current"
    cmp -s "$jivie_upgrade_work/crontab.original" "$jivie_upgrade_work/crontab.current"
    "$jivie_upgrade_crontab" "$jivie_upgrade_work/crontab.paused"
    "$jivie_upgrade_crontab" -l > "$jivie_upgrade_work/crontab.current"
    "$jivie_upgrade_php" "$jivie_upgrade_helper" --record-paused
    printf '%s\n' 'Only five staging Jivie worker lines are paused. Wait at least 65 seconds before snapshot.'
    ;;
  snapshot)
    "$jivie_upgrade_crontab" -l > "$jivie_upgrade_work/crontab.current"
    jivie_upgrade_user=$(id -un)
    /bin/ps -u "$jivie_upgrade_user" -o args= > "$jivie_upgrade_work/processes.current"
    if awk -v site='/home/tripar13/jivie-test.triparna.si' '
      index($0,site "/") && $0 ~ /(^|[ \/])(php[0-9.]*|lsphp)([ :]|$)/ { found=1 }
      END { exit !found }' "$jivie_upgrade_work/processes.current"; then
      printf '%s\n' 'Snapshot stopped: an existing staging PHP request or worker is still active.' >&2
      exit 1
    else
      jivie_upgrade_scan_status=$?
      test "$jivie_upgrade_scan_status" -eq 1
    fi
    "$jivie_upgrade_php" -r 'echo hash_file("sha256",$argv[1]);' "$jivie_upgrade_work/crontab.paused" > "$jivie_upgrade_work/workers.drained"
    "$jivie_upgrade_php" "$jivie_upgrade_helper" --snapshot
    ;;
  bundle-backup)
    "$jivie_upgrade_php" "$jivie_upgrade_helper" --bundle-backup
    ;;
  activate)
    "$jivie_upgrade_crontab" -l > "$jivie_upgrade_work/crontab.current"
    "$jivie_upgrade_php" "$jivie_upgrade_helper" --activate
    ;;
  release)
    "$jivie_upgrade_crontab" -l > "$jivie_upgrade_work/crontab.current"
    cmp -s "$jivie_upgrade_work/crontab.paused" "$jivie_upgrade_work/crontab.current"
    "$jivie_upgrade_php" "$jivie_upgrade_helper" --pre-release
    "$jivie_upgrade_crontab" "$jivie_upgrade_work/crontab.original"
    "$jivie_upgrade_crontab" -l > "$jivie_upgrade_work/crontab.current"
    "$jivie_upgrade_php" "$jivie_upgrade_helper" --release
    ;;
  abort-before-activation)
    "$jivie_upgrade_crontab" -l > "$jivie_upgrade_work/crontab.current"
    "$jivie_upgrade_php" "$jivie_upgrade_helper" --abort-check
    "$jivie_upgrade_crontab" "$jivie_upgrade_work/crontab.original"
    "$jivie_upgrade_crontab" -l > "$jivie_upgrade_work/crontab.current"
    "$jivie_upgrade_php" "$jivie_upgrade_helper" --abort
    ;;
  capture-recovery)
    "$jivie_upgrade_crontab" -l > "$jivie_upgrade_work/crontab.current"
    "$jivie_upgrade_php" "$jivie_upgrade_helper" --capture-recovery
    ;;
  rollback-code)
    "$jivie_upgrade_php" "$jivie_upgrade_helper" --rollback-code
    ;;
  *) printf '%s\n' 'Usage: upgrade-cpanel-jivie-sharing.sh prepare|pause|snapshot|bundle-backup|activate|release|abort-before-activation|capture-recovery|rollback-code' >&2; exit 2 ;;
esac
