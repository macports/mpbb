#!/bin/sh

if [[ -z "$PORTLISTFILE" ]]; then
    PORTLISTFILE=portlist
fi
if [[ -z "$PREFIX" ]]; then
    PREFIX="/opt/local"
fi
# FIXME: configure these
# download server hostname
if [[ -z "$DLHOST" ]]; then
    DLHOST=""
fi
# path where it keeps archives
if [[ -z "$DLPATH" ]]; then
    DLPATH="/archives"
fi
# private key to use for signing
if [[ -z "$PRIVKEY" ]]; then
    PRIVKEY=""
fi


for portname in `cat $PORTLISTFILE`; do
    if ls logs-*/success/${portname}.log > /dev/null 2>&1 ; then
        if ./mpexport/base/portmgr/jobs/port_binary_distributable.tcl ${portname}; then
            echo $portname is distributable
            portversion=$(${PREFIX}/bin/port info --version --line ${portname})
            portrevision=$(${PREFIX}/bin/port info --revision --line ${portname})
            for archive in ${PREFIX}/var/macports/software/${portname}/${portname}-${portversion}_${portrevision}[+.]*; do
                aname=$(basename $archive)
                echo deploying archive: $aname
                if [[ -n "$PRIVKEY" ]]; then
                    openssl dgst -ripemd160 -sign "${PRIVKEY}" -out ./${aname}.rmd160 ${archive}
                fi
                if [[ -n "$DLHOST" ]]; then
                    ssh ${DLHOST} mkdir -p ${DLPATH}/${portname}
                    rsync -av --ignore-existing ./${aname}.rmd160 ${archive} ${DLHOST}:${DLPATH}/${portname}
                fi
                rm -f ./${aname}.rmd160
            done
        else
            echo $portname is not distributable
        fi
    fi
done
