#!/bin/sh
set -eu
umask 077
test "$#" -ge 2
reset_work=$1; shift
test "$(CDPATH= cd -- "$reset_work" && pwd -P)" = "$reset_work"
reset_php='/opt/alt/php84/usr/bin/php'
reset_site=$("$reset_php" -r 'require $argv[1]; echo SITE;' "$reset_work/deployment.php")
refresh() {
 /bin/crontab -l > "$reset_work/crontab.current"
 reset_user=$(id -un)
 /bin/ps -u "$reset_user" -o args= > "$reset_work/processes.current"
 if awk -v site="$reset_site" 'index($0,site "/") && $0 ~ /(^|[ \/])(php[0-9.]*|lsphp)([ :]|$)/ { found=1 } END { exit !found }' "$reset_work/processes.current"; then
  printf '%s\n' 'Stopped: a target PHP worker/request remains active.' >&2; exit 1
 else reset_scan=$?; test "$reset_scan" -eq 1; fi
 "$reset_php" -r 'echo hash_file("sha256",$argv[1]);' "$reset_work/crontab.paused" > "$reset_work/workers.drained"
 chmod 600 "$reset_work/workers.drained"
}
case "${1-}" in
 prepare)
  test ! -e "$reset_work/crontab.original"
  /bin/crontab -l > "$reset_work/crontab.original"
  chmod 600 "$reset_work/crontab.original"
  "$reset_php" "$reset_work/backup.php" --check
  "$reset_php" "$reset_work/maintenance.php" --prepare
  "$reset_php" "$reset_work/reset.php" --inspect
  ;;
 inspect) "$reset_php" "$reset_work/reset.php" --inspect ;;
 pause)
  /bin/crontab -l > "$reset_work/crontab.current"
  cmp -s "$reset_work/crontab.original" "$reset_work/crontab.current"
  /bin/crontab "$reset_work/crontab.paused"
  /bin/crontab -l > "$reset_work/crontab.current"
  "$reset_php" "$reset_work/maintenance.php" --pause
  ;;
 export) refresh; "$reset_php" "$reset_work/backup.php" --export ;;
 stage|apply|verify|release-http)
  test "$#" -eq 3
  refresh
  "$reset_php" "$reset_work/reset.php" "--$1" "$2" "$3"
  ;;
 release-workers)
  test "$#" -eq 1
  /bin/crontab -l > "$reset_work/crontab.current"
  cmp -s "$reset_work/crontab.paused" "$reset_work/crontab.current"
  "$reset_php" "$reset_work/reset.php" --worker-release-check
  "$reset_php" "$reset_work/public-check.php"
  /bin/crontab "$reset_work/crontab.original"
  /bin/crontab -l > "$reset_work/crontab.current"
  cmp -s "$reset_work/crontab.original" "$reset_work/crontab.current"
  "$reset_php" "$reset_work/reset.php" --confirm-workers-released
  ;;
 *) printf '%s\n' 'Usage: WORK prepare|inspect|pause|export|stage ARCHIVE SHA|apply ARCHIVE SHA|verify ARCHIVE SHA|release-http ARCHIVE SHA|release-workers' >&2;exit 2 ;;
esac
