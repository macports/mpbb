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
set dependents [dict create]
set a_dependency [dict create]
foreach source $macports::sources {
    set source [lindex $source 0]
    macports_try -pass_signal {
        set fd [open [macports::getindex $source] r]

        macports_try -pass_signal {
            while {[gets $fd line] >= 0} {
                lassign $line name len
                set portinfo [read $fd $len]

                # depends_test is not included because mpbb doesn't run `port test'
                foreach field {depends_build depends_extract depends_fetch depends_lib depends_patch depends_run} {
                    if {[dict exists $portinfo $field]} {
                        foreach dependency [dict get $portinfo $field] {
                            set lowercase_dependency_name [string tolower [lindex [split $dependency :] end]]
                            dict incr dependents $lowercase_dependency_name
                            dict set a_dependency $lowercase_dependency_name $name
                        }
                    }
                }
            }
        } on error {} {
            ui_warn "It looks like your PortIndex file for $source may be corrupt."
            throw
        } finally {
            close $fd
        }
    } on error {} {
        ui_warn "Can't open index file for source: $source"
    }
}

proc removal_reason {installed_name} {
    global dependents a_dependency
    set reason ""
    set lowercase_name [string tolower $installed_name]
    if {![dict exists $dependents $lowercase_name]} {
        set reason "no port in the PortIndex depends on $installed_name"
    } elseif {[dict get $dependents $lowercase_name] == 1} {
        set dependency_reason [removal_reason [dict get $a_dependency $lowercase_name]]
        if {$dependency_reason ne ""} {
            set reason "only [dict get $a_dependency $lowercase_name] depends on $installed_name and $dependency_reason"
        }
    }
    return $reason
}

# Deactivate the given port, first deactivating any active dependents
# it has.
proc deactivate_with_dependents {e} {
    if {[$e state] ne "installed"} {
        return
    }
    foreach dependent [$e dependents] {
        deactivate_with_dependents $dependent
    }
    set options [dict create ports_nodepcheck 1]
    if {![registry::run_target $e deactivate $options]
              && [catch {portimage::deactivate [$e name] [$e version] [$e revision] [$e variants] $options} result]} {
        puts stderr $::errorInfo
        puts stderr "Deactivating [$e name] @[$e version]_[$e revision][$e variants] failed: $result"
    }
}

set uninstall_options [dict create ports_force 1]
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
        set portinfo [lindex $portindex_match 1]

        set portspec "$installed_name @${installed_version}_$installed_revision$installed_variants"
        if {[dict get $portinfo version] ne $installed_version || [dict get $portinfo revision] != $installed_revision} {
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
                    ui_msg "Not removing $portspec because it has [dict get $dependents $lowercase_name] dependents"
                }
            }
        }
    }
    if {$uninstall} {
        # Deactivate any active dependents first
        foreach dependent [$port dependents] {
            deactivate_with_dependents $dependent
        }
        # Try to run the target via the portfile first, so pre/post code runs
        if {![registry::run_target $port uninstall $uninstall_options]} {
            # Portfile failed, use the registry directly
            registry_uninstall::uninstall $installed_name $installed_version $installed_revision $installed_variants $uninstall_options
        }
    }
}

# Deactivate anything with inactive dependencies
# (can happen with non-port: deps)
# https://trac.macports.org/ticket/68662

# Track if each port has any version active
# (ports may have multiple installed variants, e.g. universal)
set has_active [dict create]
foreach port [registry::entry installed] {
    foreach dep [$port dependencies] {
        if {![dict exists $has_active [$dep name]]} {
            dict set has_active [$dep name] [expr {[registry::entry installed [$dep name]] ne ""}]
        }
        if {![dict get $has_active [$dep name]]} {
            ui_msg "Deactivating [$port name] because its dependency [$dep name] is not active"
            deactivate_with_dependents $port
            break
        }
    }
}

mportshutdown
exit 0
