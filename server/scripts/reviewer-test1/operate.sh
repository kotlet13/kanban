#!/bin/sh
set -eu
umask 077
review_work='/home/tripar13/private/jivie-test/review-upgrade-0.13.0-20261013'
review_php='/opt/alt/php84/usr/bin/php'
refresh() {
 /bin/crontab -l > "$review_work/crontab.current"
 review_user=$(id -un)
 /bin/ps -u "$review_user" -o args= > "$review_work/processes.current"
 if awk -v site='/home/tripar13/jivie-test.triparna.si' 'index($0,site "/") && $0 ~ /(^|[ \/])(php[0-9.]*|lsphp)([ :]|$)/ { found=1 } END { exit !found }' "$review_work/processes.current"; then
  printf '%s\n' 'Stopped: a test1 PHP worker/request is still active.' >&2; exit 1
 else
  review_scan_status=$?; test "$review_scan_status" -eq 1
 fi
 "$review_php" -r 'echo hash_file("sha256",$argv[1]);' "$review_work/crontab.paused" > "$review_work/workers.drained"
 chmod 600 "$review_work/workers.drained"
}
case "${1-}" in
 prepare)
  test ! -e "$review_work/crontab.original"
  /bin/crontab -l > "$review_work/crontab.original"
  chmod 600 "$review_work/crontab.original"
  "$review_php" "$review_work/backup.php" --check
  "$review_php" "$review_work/upgrade.php" --check
  "$review_php" "$review_work/maintenance.php" --prepare
  ;;
 pause)
  /bin/crontab -l > "$review_work/crontab.current"
  cmp -s "$review_work/crontab.original" "$review_work/crontab.current"
  /bin/crontab "$review_work/crontab.paused"
  /bin/crontab -l > "$review_work/crontab.current"
  "$review_php" "$review_work/maintenance.php" --pause
  ;;
 export) refresh; "$review_php" "$review_work/backup.php" --export ;;
 stage|apply|verify)
  test "$#" -eq 3
  refresh
  if test "$1" = stage; then "$review_php" "$review_work/upgrade.php" --stage "$2" "$3"; else "$review_php" "$review_work/upgrade.php" "--$1" "$3"; fi
  ;;
 release)
  test "$#" -eq 2
  refresh
  "$review_php" "$review_work/upgrade.php" --verify "$2"
  cmp -s "$review_work/crontab.paused" "$review_work/crontab.current"
  /bin/crontab "$review_work/crontab.original"
  /bin/crontab -l > "$review_work/crontab.current"
  "$review_php" "$review_work/upgrade.php" --release "$2"
  ;;
 *) printf '%s\n' 'Usage: prepare|pause|export|stage ARCHIVE SHA|apply ARCHIVE SHA|verify ARCHIVE SHA|release SHA' >&2; exit 2 ;;
esac
