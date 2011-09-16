#!/bin/sh

if [[ -z "$PREFIX" ]]; then
    PREFIX=/opt/local
fi
if [[ -z "$ULPATH" ]]; then
    ULPATH=archive_staging
fi
if [[ -z "$TOPDIR" ]]; then
    TOPDIR=.
fi

rm -vrf ${TOPDIR}/logs-*
rm -vrf ${TOPDIR}/${ULPATH}
rm -vrf ${PREFIX}/var/macports/distfiles/*

oldports=`./oldports.tcl -t "${PREFIX}/share/macports/Tcl"`
if [[ -n "$oldports" ]]; then
    echo $oldports | xargs "${PREFIX}/bin/port" -f uninstall
fi
