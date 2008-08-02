MacPorts AutoBuild
Version 0.5, 2008-05-31

Introduction
------------
MacPorts AutoBuild (mpab) is a set of scripts which creates a chroot
environment in which to run MacPorts and build the entire group of ports
available to it.  Once complete (which could take a long time) or stopped,
the build logs are moved out of the chroot to be available for review.


Prerequisites
-------------
You need to have 10.5, Xcode 3.0, and Apple's X11 (other versions of Xcode
and X11 may work, but these are the ones tested so far).

For the MacPorts which will live in the chroot, you'll need (in the same
directory as the mpab script) a tarball named macports_dist.tar.bz2.  To
create this straight from the MacPorts svn server (assuming current
working directory is the same as the mpab script):

   svn export http://svn.macports.org/repository/macports/trunk mpexport
   cd mpexport
   tar cf - . | bzip2 -c > ../macports_dist.tar.bz2
   cd ..
   rm -rf mpexport

This just exports it from svn (since the .svn stuff isn't needed for this)
then creates the tarball; note everything in the tarball is based on the
current working directory.

If you already have MacPorts from svn, run this instead of the first command
above, then do the rest:
   svn export /path/to/macports/svn/trunk mpexport


Installation
------------
Once the MPAB tarball is extracted (which you've probably done if you're
reading this), make sure the above prerequisites are available, then you
are ready to go


Running
-------
To just build it all (every port):

   sudo ./mpab

(assuming you are in the directory with the mpab script).  This will do
what needs doing to get a chroot, install MacPorts in said chroot, then
start building ports.

The first time you run, it will take some time as it is creating a chroot
environment, which involves copying several gigabytes of files into
said chroot...be patient.

You can also run 'sudo ./mpab help' to see what commands can be used with
mpab.


Maintenance
-----------
mpab creates several disk images:

   mproot.dmg - this is the basic chroot environment with various system
                programs installed; it is read-only
   mproot.dmg.shadow - this is where updates to the chroot go, which means
                       to restart with a bare chroot, simply delete it and
                       all traces of MacPorts are gone
   mproot_distcache.sparseimage - this is a disk image only containing the
                                  distfiles MacPorts downloads (which are
                                  in /opt/local/var/macports/distfiles)

When the OS version is updated, both mproot.dmg and mproot.dmg.shadow
should be deleted so they can be rebuilt.  Any time you want to clean out
the MacPorts stuff within the chroot but not rebuild the entire environment,
you can delete just mproot.dmg.shadow, to start from scratch.  Note if you
want to rebuild MacPorts, mpab has a rebuildmp target to do just that.


Todo
----
improve the amount of debugging available via MPABDEBUG

add 10.4 support (mostly needs different paths in pathsToCreate and
pathsToCopy in buildImages())

add a method to allow variants either globally or to an individual port

fix dependency checking to work more like MP; currently if a port fails, all
those depending on it are skipped, but if it's lib:...:port then it might
still be buildable (see some things which depend on gnutar, and this will
allow to skip the XFree86/xorg special-casing)

