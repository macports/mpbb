#!/bin/sh

exportDir=mpexport

CHROOTSUBDIR=mpchroot

baseDir=$(dirname $0)

dataDir=$(pwd)
if [[ $MPAB_DATA ]]; then
   dataDir=$MPAB_DATA
fi

chrootPath="${dataDir}/${CHROOTSUBDIR}"

# $1 - script to execute
function chroot_exec () {
    cp -p ${baseDir}/chroot-scripts/$1 ${chrootPath}/var/tmp/
    # Set DYLD_NO_FIX_PREBINDING as otherwise, on 10.5, dyld will spew
    # errors to syslog/console log like:
    # com.apple.launchd[1] (com.apple.dyld): Throttling respawn: Will start in 10 seconds
    env -i PATH=/bin:/usr/bin:/sbin:/usr/sbin HOME=/var/root DYLD_NO_FIX_PREBINDING=1 /usr/sbin/chroot ${chrootPath} /bin/sh /var/tmp/$1
    rm ${chrootPath}/var/tmp/$1
}

if [[ -d ${dataDir}/${exportDir} ]] ; then 
    svn update --non-interactive \
	-r HEAD ${dataDir}/${exportDir} \
	> /dev/null || exit 1
else
    echo "Checking out macports from svn..."
    svn checkout --non-interactive -r HEAD \
	https://svn.macports.org/repository/macports/trunk \
	${dataDir}/${exportDir} > /dev/null || exit 1
fi

if [[ ! -d ${dataDir}/mpchroot ]] ; then
    sudo ${baseDir}/mpab mount || exit 1
    umount=yes
fi

rsync -r --del --exclude '*~' --exclude '.svn' \
    ${dataDir}/${exportDir}/dports \
    ${dataDir}/mpchroot/opt/mports || exit 1

echo "Re-creating portindex in chroot"
chroot_exec recreateportindex

if [[ "${umount}" = yes ]] ; then
    sudo ${baseDir}/mpab umount || exit 1
fi
