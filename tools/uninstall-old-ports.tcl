#!/usr/bin/env port-tclsh

proc printUsage {} {
    puts "Usage: $::argv0 \[-hV\]"
    puts "  -h    This help"
    puts "  -V    show version and MacPorts version being used"
}

set MY_VERSION 0.2

set showVersion 0

set origArgv $::argv
while {[string index [lindex $::argv 0] 0] == "-" } {
    switch [string range [lindex $::argv 0] 1 end] {
        h {
            printUsage
            exit 0
        }
        V {
            set showVersion 1
        }
        default {
            puts "Unknown option [lindex $::argv 0]"
            printUsage
            exit 2
        }
    }
    set ::argv [lrange $::argv 1 end]
}

package require macports
mportinit

if {$showVersion} {
    puts "uninstall-old-ports.tcl version $MY_VERSION"
    puts "MacPorts version [macports::version]"
    exit 0
}

##
# Compare two versions in the form of (epoch, version, revision).
#
# @param versionA Tcl array of the first version with the keys epoch, version, and revision.
# @param versionB Tcl array of the second version in the same format as versionA.
# @return An integer < 0 if the first version is smaller than the second. 0, if
#         both versions are equal. An integer > 0 if the second version is
#         larger than the first.
proc compare_version_tuple {versionA versionB} {
    upvar $versionA vA
    upvar $versionB vB

    set epochCompare    [vercmp $vA(epoch) $vB(epoch)]
    set versionCompare  [vercmp $vA(version) $vB(version)]
    set revisionCompare [vercmp $vA(revision) $vB(revision)]

    if {$epochCompare != 0} {
        return $epochCompare
    }
    if {$versionCompare != 0} {
        return $versionCompare
    }
    return $revisionCompare
}

foreach port [registry::installed] {
    # Set to yes if a port is obsolete
    set old no

    set installed_name [lindex $port 0]
    set installed_version [lindex $port 1]
    set installed_revision [lindex $port 2]
    set installed_variants [lindex $port 3]
    set installed_epoch [lindex $port 5]

    array set installed_version_tuple {}
    set installed_version_tuple(epoch) $installed_epoch
    set installed_version_tuple(version) $installed_version
    set installed_version_tuple(revision) $installed_revision

    set portindex_match [mportlookup $installed_name]
    if {[llength $portindex_match] < 2} {
        # Not found in index, classify as old
		ui_msg "Removing $installed_name$installed_variants $installed_epoch@$installed_version-$installed_revision because it is no longer in the PortIndex"
        set old yes
    } else {
        array unset portinfo
        array set portinfo [lindex $portindex_match 1]

        set result [compare_version_tuple portinfo installed_version_tuple]
        if {$result > 0} {
            # Port is outdated because the version in the index is newer than
            # the installed one
			ui_msg "Removing $installed_name$installed_variants $installed_epoch@$installed_version-$installed_revision because there is a newer version in the PortIndex"
            set old yes
        }
        # If the version we have is newer than the one in the PortIndex, we are
        # probably building agaist an old version of the ports tree.
    }
    if {$old} {
        registry::uninstall $installed_name $installed_version $installed_revision $installed_variants [list ports_force 1]
    }
}
