#!/bin/sh
set -eu
umask 077
test "$#" -eq 2
sound_work=$1
sound_mode=$2
test "$(CDPATH= cd -- "$sound_work" && pwd -P)" = "$sound_work"
case "$sound_mode" in check|apply) ;; *) exit 2 ;; esac
/bin/crontab -l > "$sound_work/crontab.current"
chmod 600 "$sound_work/crontab.current"
/opt/alt/php84/usr/bin/php "$sound_work/patch.php" "--$sound_mode"
