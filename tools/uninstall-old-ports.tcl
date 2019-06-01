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

# Create a lookup table for determining whether a port has dependents
# (regardless of whether or not those dependents are currently installed)
foreach source $macports::sources {
    set source [lindex $source 0]
    try -pass_signal {
        set fd [open [macports::getindex $source] r]

        try -pass_signal {
            while {[gets $fd line] >= 0} {
                array unset portinfo
                set name [lindex $line 0]
                set len  [lindex $line 1]
                set line [read $fd $len]
                array set portinfo $line

                # depends_test is not included because mpbb doesn't run `port test'
                foreach field {depends_build depends_extract depends_fetch depends_lib depends_patch depends_run} {
                    if [info exists portinfo($field)] {
                        foreach dependency $portinfo($field) {
                            set dependency_name [lindex [split $dependency {:}] end]
                            incr dependents([string tolower $dependency_name])
                        }
                    }
                }
            }
        } catch {*} {
            ui_warn "It looks like your PortIndex file for $source may be corrupt."
            throw
        } finally {
            close $fd
        }
    } catch {*} {
        ui_warn "Can't open index file for source: $source"
    }
}

foreach port [registry::entry imaged] {
    # Set to yes if a port should be uninstalled
    set uninstall no

    set installed_name [$port name]
    set installed_version [$port version]
    set installed_revision [$port revision]
    set installed_variants [$port variants]

    set portindex_match [mportlookup $installed_name]
    if {[llength $portindex_match] < 2} {
        # Not found in index
        ui_msg "Removing ${installed_name} @${installed_version}_${installed_revision}${installed_variants} because it is no longer in the PortIndex"
        set uninstall yes
    } else {
        array unset portinfo
        array set portinfo [lindex $portindex_match 1]

        if {$portinfo(version) ne $installed_version || $portinfo(revision) != $installed_revision} {
            # The version in the index is different than the installed one
            ui_msg "Removing ${installed_name} @${installed_version}_${installed_revision}${installed_variants} because there is a newer version in the PortIndex"
            set uninstall yes
        } else {
            set lowercase_name [string tolower $installed_name]
            if {![info exists dependents($lowercase_name)]} {
                # Nothing depends on it
                ui_msg "Removing ${installed_name} @${installed_version}_${installed_revision}${installed_variants} because no port in the PortIndex depends on it"
                set uninstall yes
            } elseif {no} {
                ui_msg "Not removing ${installed_name} @${installed_version}_${installed_revision}${installed_variants} because it has $dependents($lowercase_name) dependents"
            }
        }
    }
    if {$uninstall} {
        registry_uninstall::uninstall $installed_name $installed_version $installed_revision $installed_variants [list ports_force 1]
    }
}
