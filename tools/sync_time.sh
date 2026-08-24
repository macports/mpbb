#! /bin/bash
# -*- coding: utf-8; mode: sh; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- vim:fenc=utf-8:ft=sh:et:sw=4:ts=4:sts=4

if [ "$(id -u)" -ne 0 ]; then
    # Can't adjust clock if not root
    exit 0
fi

timeserver="time.apple.com"

# Find out how far off the system clock is from the timeserver
# (truncate to whole seconds since we don't really care if it's small)
if [ -x /usr/sbin/ntpdate ]; then
    offset="$(/usr/sbin/ntpdate -q $timeserver | tail -n1 | grep -Eo '[0-9.+-]+ sec$' | cut -d . -f 1)"
elif [ -x /usr/bin/sntp ]; then
    offset="$(/usr/bin/sntp $timeserver | tail -n1 | cut -d . -f 1)"
else
    echo "Don't know how to query the time server"
    exit 0
fi

if [ -z "$offset" ]; then
    echo "Failed to get time offset"
    exit 0
fi

if [ "$offset" -ge 10 -o "$offset" -le -10 ]; then
    echo "Time is off by $offset seconds, syncing"
    if [ -e /usr/libexec/timed ]; then
        # This unfortunately seems to be the only way to force timed to
        # sync the time immediately.
        rm -rf /var/db/timed/Library /var/db/timed/com.apple.timed.plist
        launchctl kill INT system/com.apple.timed
    else
        /usr/sbin/ntpdate "$timeserver"
    fi
fi
