#!/bin/sh

exportDir=mpexport

CHROOTSUBDIR=mpchroot

baseDir=$(dirname $0)

dataDir=$(pwd)
if [[ -n "$MPAB_DATA" ]]; then
   dataDir=$MPAB_DATA
fi
if [[ -z "$PREFIX" ]]; then
   PREFIX=/opt/local
fi
if [[ -z "$SRC_PREFIX" ]]; then
   SRC_PREFIX=/opt/mports
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

# $1 - script to execute
function chroot_exec () {
    cp -p ${baseDir}/chroot-scripts/$1 ${chrootPath}/var/tmp
    if [[ -n "$chrootPath" ]]; then
        # Set DYLD_NO_FIX_PREBINDING as otherwise, on 10.5, dyld will spew
        # errors to syslog/console log like:
        # com.apple.launchd[1] (com.apple.dyld): Throttling respawn: Will start in 10 seconds
        env -i PATH=/bin:/usr/bin:/sbin:/usr/sbin HOME=/var/root DYLD_NO_FIX_PREBINDING=1 PREFIX=${PREFIX} SRC_PREFIX=${SRC_PREFIX} /usr/sbin/chroot ${chrootPath} /bin/sh /var/tmp/$1
    else
        env -i PATH=/bin:/usr/bin:/sbin:/usr/sbin HOME=/var/root PREFIX=${PREFIX} SRC_PREFIX=${SRC_PREFIX} /bin/sh /var/tmp/$1
    fi
    rm ${chrootPath}/var/tmp/$1
}

if [[ -d ${dataDir}/${exportDir} ]] ; then 
    svn update --non-interactive \
	-r HEAD ${dataDir}/${exportDir}/* || exit 1
else
    echo "Checking out macports from svn..."
    svn checkout --non-interactive -r HEAD \
	https://svn.macports.org/repository/macports/trunk \
	${dataDir}/${exportDir} || exit 1
fi

if [[ -n "$chrootPath" && ! -d "$chrootPath" ]] ; then
    sudo ${baseDir}/mpab mount || exit 1
    umount=yes
fi

rsync -av --del --exclude '*~' --exclude '.svn' \
    ${dataDir}/${exportDir} \
    ${chrootPath}${SRC_PREFIX} || exit 1

echo "Re-creating portindex"
chroot_exec recreateportindex

if [[ "${umount}" = yes ]] ; then
    sudo ${baseDir}/mpab umount || exit 1
fi
