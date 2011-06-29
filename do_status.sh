#!/bin/sh

if [[ -z "$PORTLISTFILE" ]]; then
    PORTLISTFILE=portlist
fi
if [[ -z "$PREFIX" ]]; then
    PREFIX="../opt/local"
fi
if [[ -z "$STATUS_LOG" ]]; then
    STATUS_LOG=portstatus.log
fi


rm -f $STATUS_LOG
failed=0
for portname in `cat $PORTLISTFILE`; do
    if ls logs-*/success/${portname}.log > /dev/null 2>&1 ; then
        echo "[OK] ${portname}" >> $STATUS_LOG
    elif ls logs-*/failure/${portname}.log > /dev/null 2>&1 ; then
        echo "[FAIL] ${portname}" >> $STATUS_LOG
        let "failed = failed + 1"
        # send email to appropriate places
        portmaintainers=$(${PREFIX}/bin/port info --maintainers --line ${portname} | tr ',' ' ')
        for maint in $portmaintainers; do
            if [[ "$maint" != "nomaintainer@macports.org" && "$maint" != "openmaintainer@macports.org" ]]; then
                # email maintainer
                echo "not emailing $maint (not set up yet)"
            fi
            # also send to some new mailing list?
        done
    fi
done
exit $failed
