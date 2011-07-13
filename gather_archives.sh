#!/bin/sh

if [[ -z "$PORTLISTFILE" ]]; then
    PORTLISTFILE=portlist
fi

if [[ -z "$PREFIX" ]]; then
    PREFIX="/opt/local"
fi

# path where archives should be staged before being uploaded to the master
if [[ -z "$ULPATH" ]]; then
    ULPATH="archive_staging"
fi

mkdir -p $ULPATH
for portname in `cat $PORTLISTFILE`; do
    if ls logs-*/success/${portname}.log > /dev/null 2>&1 ; then
        if ./mpexport/base/portmgr/jobs/port_binary_distributable.tcl ${portname}; then
            echo $portname is distributable
            portversion=$(${PREFIX}/bin/port info --version --line ${portname})
            portrevision=$(${PREFIX}/bin/port info --revision --line ${portname})
            for archive in ${PREFIX}/var/macports/software/${portname}/${portname}-${portversion}_${portrevision}[+.]*; do
                aname=$(basename $archive)
                echo preparing archive for upload: $aname
                mkdir -p ${ULPATH}/${portname}
                cp $archive ${ULPATH}/${portname}/
            done
        else
            echo $portname is not distributable
        fi
    fi
done
