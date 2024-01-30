#!/usr/bin/env port-tclsh
# -*- coding: utf-8; mode: tcl; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- vim:fenc=utf-8:ft=tcl:et:sw=4:ts=4:sts=4

if {[llength $::argv] < 2 || ([lindex $::argv 0] eq "-y" && [llength $::argv] < 3)} {
    puts stderr "Usage: $::argv0 \[-y\] cur_free target"
    exit 1
}
set dryrun no
if {[lindex $::argv 0] eq "-y"} {
    set dryrun yes
}
# given in KiB, convert to bytes
set cur_free [expr {[lindex $::argv end-1] * 1024}]
set target [expr {[lindex $::argv end] * 1024}]

package require macports
# for random
package require Tclx
mportinit

random seed
array set candidates {}

fs-traverse -ignoreErrors -- f [list ${macports::portdbpath}/distfiles] {
    if {[file type $f] eq "file"} {
        # 0 for distfile, 1 for port
        set candidates($f) 0
    }
}

foreach port [registry::entry imaged] {
    if {[$port dependents] eq ""} {
        set candidates($port) 1
    }
}

proc active_files_size {port} {
    set total 0
    foreach f [$port files] {
        if {![catch {file type $f} type] && $type eq "file"} {
            incr total [file size $f]
        }
    }
    return $total
}

set candidate_list [array names candidates]
# It is tempting to sort by size and delete the largest things first,
# but picking randomly greatly reduces the chance that we will just
# uninstall one huge port that will immediately be reinstalled as a
# dependency of whatever we build next.
while {$cur_free < $target && [llength $candidate_list] > 0} {
    set i [random [llength $candidate_list]]
    set chosen [lindex $candidate_list $i]
    set candidate_list [lreplace ${candidate_list}[set candidate_list {}] $i $i]
    if {$candidates($chosen) == 0} {
        set size [file size $chosen]
        incr cur_free $size
        puts "Deleting $chosen ($size bytes)"
        if {!$dryrun} {
            file delete -force $chosen
        }
    } else {
        set size [file size [$chosen location]]
        if {[$chosen state] eq "installed"} {
            incr size [active_files_size $chosen]
        }
        incr cur_free $size
        set deps [$chosen dependencies]
        puts "Uninstalling [$chosen name] @[$chosen version]_[$chosen revision][$chosen variants] ($size bytes)"
        if {!$dryrun} {
            if {![registry::run_target $chosen uninstall [list]]} {
                # Portfile failed, use the registry directly
                registry_uninstall::uninstall [$chosen name] [$chosen version] [$chosen revision] [$chosen variants] [list]
            }
        }
        foreach dep $deps {
            if {![info exists candidates($dep)] && [$dep dependents] eq ""} {
                set candidates($dep) 1
                lappend candidate_list $dep
            }
        }
    }
}

mportshutdown
exit 0
