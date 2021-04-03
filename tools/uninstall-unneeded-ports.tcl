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
    puts "uninstall-unneeded-ports.tcl version $MY_VERSION"
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
                    if {[info exists portinfo($field)]} {
                        foreach dependency $portinfo($field) {
                            set lowercase_dependency_name [string tolower [lindex [split $dependency :] end]]
                            incr dependents($lowercase_dependency_name)
                            set a_dependency($lowercase_dependency_name) $name
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

proc removal_reason {installed_name} {
    global dependents a_dependency
    set reason ""
    set lowercase_name [string tolower $installed_name]
    if {![info exists dependents($lowercase_name)]} {
        set reason "no port in the PortIndex depends on $installed_name"
    } elseif {$dependents($lowercase_name) == 1} {
        set dependency_reason [removal_reason $a_dependency($lowercase_name)]
        if {$dependency_reason ne ""} {
            set reason "only $a_dependency($lowercase_name) depends on $installed_name and $dependency_reason"
        }
    }
    return $reason
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

        set portspec "$installed_name @${installed_version}_$installed_revision$installed_variants"
        if {$portinfo(version) ne $installed_version || $portinfo(revision) != $installed_revision} {
            # The version in the index is different than the installed one
            ui_msg "Removing $portspec because there is a newer version in the PortIndex"
            set uninstall yes
        } else {
            set reason [removal_reason $installed_name]
            if {$reason ne ""} {
                set uninstall yes
                ui_msg "Removing $portspec because $reason"
            } else {
                set uninstall no
                if {no} {
                    set lowercase_name [string tolower $installed_name]
                    ui_msg "Not removing $portspec because it has $dependents($lowercase_name) dependents"
                }
            }
        }
    }
    if {$uninstall} {
        registry_uninstall::uninstall $installed_name $installed_version $installed_revision $installed_variants [list ports_force 1]
    }
}
