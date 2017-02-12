#!/usr/bin/env port-tclsh
# -*- coding: utf-8; mode: tcl; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- vim:fenc=utf-8:ft=tcl:et:sw=4:ts=4:sts=4

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

foreach port [registry::entry imaged] {
    # Set to yes if a port is not current
    set old no

    set installed_name [$port name]
    set installed_version [$port version]
    set installed_revision [$port revision]
    set installed_variants [$port variants]

    set portindex_match [mportlookup $installed_name]
    if {[llength $portindex_match] < 2} {
        # Not found in index, classify as old
        ui_msg "Removing ${installed_name} @${installed_version}_${installed_revision}${installed_variants} because it is no longer in the PortIndex"
        set old yes
    } else {
        array unset portinfo
        array set portinfo [lindex $portindex_match 1]

        if {$portinfo(version) ne $installed_version || $portinfo(revision) != $installed_revision} {
            # Port is not current because the version in the index is
            # different than the installed one
            ui_msg "Removing ${installed_name} @${installed_version}_${installed_revision}${installed_variants} because there is a newer version in the PortIndex"
            set old yes
        }
    }
    if {$old} {
        registry_uninstall::uninstall $installed_name $installed_version $installed_revision $installed_variants [list ports_force 1]
    }
}
