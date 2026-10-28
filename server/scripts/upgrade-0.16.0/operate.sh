#!/bin/sh
set -eu
umask 077
test "$#" -ge 2
review_work=$1; shift
test "$(CDPATH= cd -- "$review_work" && pwd -P)" = "$review_work"
review_site=$("/opt/alt/php84/usr/bin/php" -r 'require $argv[1]; echo SITE;' "$review_work/deployment.php")
review_php='/opt/alt/php84/usr/bin/php'
refresh() {
 /bin/crontab -l > "$review_work/crontab.current"
 review_user=$(id -un)
 /bin/ps -u "$review_user" -o args= > "$review_work/processes.current"
 if awk -v site="$review_site" 'index($0,site "/") && $0 ~ /(^|[ \/])(php[0-9.]*|lsphp)([ :]|$)/ { found=1 } END { exit !found }' "$review_work/processes.current"; then
  printf '%s\n' 'Stopped: a target PHP worker/request is still active.' >&2; exit 1
 else
  review_scan_status=$?; test "$review_scan_status" -eq 1
 fi
 "$review_php" -r 'echo hash_file("sha256",$argv[1]);' "$review_work/crontab.paused" > "$review_work/workers.drained"
 chmod 600 "$review_work/workers.drained"
}
case "${1-}" in
 prepare)
  test -x /usr/bin/timeout
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
 release-http)
  test "$#" -eq 2
  refresh
  "$review_php" "$review_work/upgrade.php" --verify "$2"
  "$review_php" "$review_work/upgrade.php" --release "$2"
  ;;
 release-workers)
  test "$#" -eq 2
  /bin/crontab -l > "$review_work/crontab.current"
  cmp -s "$review_work/crontab.paused" "$review_work/crontab.current"
  "$review_php" "$review_work/public-check.php"
  /bin/crontab "$review_work/crontab.upgraded"
  /bin/crontab -l > "$review_work/crontab.current"
  "$review_php" "$review_work/upgrade.php" --confirm-release "$2"
  ;;
 *) printf '%s\n' 'Usage: WORK prepare|pause|export|stage ARCHIVE SHA|apply ARCHIVE SHA|verify ARCHIVE SHA|release-http SHA|release-workers SHA' >&2; exit 2 ;;
esac
