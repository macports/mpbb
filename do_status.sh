#!/bin/sh

if [[ -z "$PORTLISTFILE" ]]; then
    PORTLISTFILE=portlist
fi
if [[ -z "$PREFIX" ]]; then
    PREFIX="/opt/local"
fi
if [[ -z "$STATUS_LOG" ]]; then
    STATUS_LOG=portstatus.log
fi


rm -f $STATUS_LOG
failed=0

if [[ `head -n1 $PORTLISTFILE` == "all" ]]; then
    ports=`${PREFIX}/bin/port -q echo all | tr '\n' ' '`
else
    ports=`cat $PORTLISTFILE`
fi

for portname in $ports; do
    if ls logs-*/success/${portname}.log > /dev/null 2>&1 ; then
        echo "[OK] ${portname}" >> $STATUS_LOG
    elif ls logs-*/fail/${portname}.log > /dev/null 2>&1 ; then
        echo "[FAIL] ${portname}" >> $STATUS_LOG
        let "failed = failed + 1"
    fi
done
exit $failed
