#!/bin/sh

CHROOTSUBDIR=mpchroot
dataDir=$(pwd)
if [[ -n "$MPAB_DATA" ]]; then
   dataDir=$MPAB_DATA
fi
chrootPath="${dataDir}/${CHROOTSUBDIR}"
OSMajor=`uname -r | sed 's/\..*//'`
# xcodebuild breaks in chroots on 10.6
if [[ $1 = "-n" || $OSMajor -ge 10 ]]; then
    chrootPath=""
    if [[ $1 = "-n" ]]; then
        shift
    fi
fi

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
if [[ `head -n1 $PORTLISTFILE` == "all" ]]; then
    ports=`${PREFIX}/bin/port -q echo all | tr '\n' ' '`
else
    ports=`cat $PORTLISTFILE`
fi

# if mpab was killed due to a timeout, logs will still be in the tmp dir
if ! ls logs-* > /dev/null 2>&1 ; then
    now=`date '+%Y%m%d-%H%M%S'`
    baseDir=$(dirname $0)
    mkdir ${baseDir}/logs-${now}
    mv ${chrootPath}/var/tmp/portresults/fail ${baseDir}/logs-${now}
    mv ${chrootPath}/var/tmp/portresults/success ${baseDir}/logs-${now}
    chmod -R a+rX ${baseDir}/logs-${now}
fi

for portname in $ports; do
    if ls logs-*/success/${portname}.log > /dev/null 2>&1 ; then
        if ./mpexport/base/portmgr/jobs/port_binary_distributable.tcl -v ${portname}; then
            portversion=$(${PREFIX}/bin/port info --index --version --line ${portname})
            portrevision=$(${PREFIX}/bin/port info --index --revision --line ${portname})
            for archive in ${PREFIX}/var/macports/software/${portname}/${portname}-${portversion}_${portrevision}[+.]*; do
                aname=$(basename $archive)
                echo preparing archive for upload: $aname
                mkdir -p ${ULPATH}/${portname}
                cp $archive ${ULPATH}/${portname}/
            done
        fi
    fi
done
