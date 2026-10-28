#!/bin/sh
# Reviewed pre-DDL abort. PHP cannot execute crontab on this hosting.
set -eu
umask 077
test "$#" -eq 1
abort_work=$1
abort_php='/opt/alt/php84/usr/bin/php'
test "$(CDPATH= cd -- "$abort_work" && pwd -P)" = "$abort_work"
abort_site=$("$abort_php" -r 'require $argv[1]; echo SITE;' "$abort_work/deployment.php")
/bin/crontab -l > "$abort_work/crontab.current"
abort_user=$(id -un)
/bin/ps -u "$abort_user" -o args= > "$abort_work/processes.current"
if awk -v site="$abort_site" 'index($0,site "/") && $0 ~ /(^|[ \/])(php[0-9.]*|lsphp)([ :]|$)/ { found=1 } END { exit !found }' "$abort_work/processes.current"; then
 printf '%s\n' 'Stopped: a target PHP worker/request is still active.' >&2
 exit 1
else
 abort_scan_status=$?
 test "$abort_scan_status" -eq 1
fi
"$abort_php" -r 'echo hash_file("sha256",$argv[1]);' "$abort_work/crontab.paused" > "$abort_work/workers.drained"
chmod 600 "$abort_work/workers.drained"
"$abort_php" "$abort_work/backup.php" --check
"$abort_php" "$abort_work/abort.php" --check
"$abort_php" "$abort_work/abort.php" --restore-http
# Original upgrade --check requires original HTTPS; run only after restoration.
"$abort_php" "$abort_work/upgrade.php" --check
/bin/crontab -l > "$abort_work/crontab.current"
cmp -s "$abort_work/crontab.paused" "$abort_work/crontab.current"
/bin/crontab "$abort_work/crontab.original"
/bin/crontab -l > "$abort_work/crontab.current"
"$abort_php" "$abort_work/abort.php" --confirm-cron
