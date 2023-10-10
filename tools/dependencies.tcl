#!/usr/bin/env port-tclsh
# -*- coding: utf-8; mode: tcl; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- vim:fenc=utf-8:ft=tcl:et:sw=4:ts=4:sts=4
#
# Ensure that all dependencies needed to install a given port are active.
#
# Copyright (c) 2016 The MacPorts Project.
# Copyright (c) 2016 Clemens Lang <cal@macports.org>
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in
#    the documentation and/or other materials provided with the
#    distribution.
# 3. Neither the name of the MacPorts project, nor the names of any contributors
#    may be used to endorse or promote products derived from this software
#    without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS ``AS IS''
# AND ANY EXPRESSED OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS
# BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
# BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
# OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN
# IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

set start_time [clock seconds]

package require macports
package require registry2

source [file join [file dirname [info script]] failcache.tcl]

set failcache_dir ""
set logs_dir ""
while {[string range [lindex $::argv 0] 0 1] eq "--"} {
    switch -- [lindex $::argv 0] {
        --failcache_dir {
            set failcache_dir [lindex $::argv 1]
            set ::argv [lreplace $::argv 0 0]
        }
        --logs_dir {
            set logs_dir [lindex $::argv 1]
            set ::argv [lreplace $::argv 0 0]
        }
        default {
            ui_error "unknown option: [lindex $::argv 0]"
            exit 2
        }
    }
    set ::argv [lreplace $::argv 0 0]
}

if {$logs_dir ne ""} {
    set log_status_dependencies [open ${logs_dir}/dependencies-progress.txt w]
    set log_subports_progress [open ${logs_dir}/ports-progress.txt a]
} else {
    set log_status_dependencies [open /dev/null a]
    set log_subports_progress $log_status_dependencies
}

if {[llength $::argv] == 0} {
    puts stderr "Usage: $argv0 <portname> \[(+|-)variant...\]"
    exit 2
}

# initialize macports
set my_global_options(ports_nodeps) yes
if {[catch {mportinit "" my_global_options ""} result]} {
   ui_error "$errorInfo"
   ui_error "Failed to initialize ports system: $result"
   exit 2
}

# look up the path of the Portfile for the given port
set portname [lindex $::argv 0]
#try -pass_signal {...}
try {
    set result [mportlookup $portname]
    if {[llength $result] < 2} {
        ui_error "No such port: $portname"
        exit 1
    }
} on error {eMessage} {
    ui_error "mportlookup $portname failed: $eMessage"
    exit 2
}

# parse the given variants from the command line
array set variants {}
foreach item [lrange $::argv 1 end] {
    foreach {_ sign variant} [regexp -all -inline -- {([-+])([[:alpha:]_]+[\w\.]*)} $item] {
        set variants($variant) $sign
    }
}

# open the port so we can run dependency calculation
array set portinfo [lindex $result 1]
#try -pass_signal {...}
try {
    set mport [mportopen $portinfo(porturl) [list subport $portinfo(name)] [array get variants]]
} on error {eMessage} {
    ui_error "mportopen ${portinfo(porturl)} failed: $eMessage"
    exit 2
}

array set portinfo [mportinfo $mport]
# Also checking for matching archive, in case supported_archs changed
if {[registry::entry imaged $portinfo(name) $portinfo(version) $portinfo(revision) $portinfo(canonical_active_variants)] ne ""
        && [[ditem_key $mport workername] eval [list _archive_available]]} {
    puts "$::argv already installed, not installing or activating dependencies"
    exit 0
}
# Ensure build-time deps are always included for the top-level port,
# because CI will do a build of all ports affected by a commit even if
# the version hasn't changed and an archive is available. This
# shouldn't result in unnecessary installations, because the check
# above will skip installing deps for already installed ports, and the
# buildbot will exclude ports that have an archive deployed.
[ditem_key $mport workername] eval [list set portutil::archive_available_result 0]

set toplevel_depstypes [list depends_fetch depends_extract depends_patch depends_build depends_lib depends_run]
set recursive_depstypes [list depends_lib depends_run]
foreach p [split $env(PATH) :] {
    if {![string match ${macports::prefix}* $p]} {
        lappend bin_search_path $p
    }
}
set lib_search_path [list /Library/Frameworks /System/Library/Frameworks /lib /usr/lib]

# check if depspec is fulfilled by a port, and if so, append its
# name to the variable named by retvar
proc check_dep_needs_port {depspec retvar} {
    upvar $retvar ret
    set splitlist [split $depspec :]
    set portname [lindex $splitlist end]
    set depregex [lindex $splitlist 1]
    switch [lindex $splitlist 0] {
        bin {
            set depregex \^$depregex\$
            set search_path $::bin_search_path
            set executable 1
        }
        lib {
            set search_path $::lib_search_path
            set i [string first . $depregex]
            if {$i < 0} {set i [string length $depregex]}
            set depname [string range $depregex 0 ${i}-1]
            set depversion [string range $depregex $i end]
            regsub {\.} $depversion {\.} depversion
            set depregex \^${depname}${depversion}\\.dylib\$
            set executable 0
        }
        path {
            # separate directory from regex
            set fullname $depregex
            regexp {^(.*)/(.*?)$} $fullname match search_path depregex
            if {[string index $search_path 0] ne "/"
                || [string match ${macports::prefix}* $search_path]} {
                # Path in prefix, can be assumed to be from a port
                lappend ret $portname
                return
            }
            set depregex \^$depregex\$
            set executable 0
        }
        port {
            lappend ret $portname
            return
        }
    }
    if {![_mportsearchpath $depregex $search_path $executable]} {
        lappend ret $portname
    }
}

# Get the ports needed by a given port.
proc collect_deps {portinfovar retvar} {
    upvar $portinfovar portinfo
    upvar $retvar ret
    foreach deptype $::recursive_depstypes {
        if {[info exists portinfo($deptype)]} {
            foreach depspec $portinfo($deptype) {
                check_dep_needs_port $depspec ret
            }
        }
    }
}

# return maintainer email addresses for the given port names
proc get_maintainers {args} {
    set retlist [list]
    foreach portname $args {
        try {
            set result [mportlookup $portname]
            if {[llength $result] < 2} {
                continue
            }
        } on error {eMessage} {
            ui_error "mportlookup $portname failed: $eMessage"
            continue
        }
        array unset portinfo
        array set portinfo [lindex $result 1]
        foreach sublist [macports::unobscure_maintainers $portinfo(maintainers)] {
            foreach {key value} $sublist {
                if {$key eq "email"} {
                    lappend retlist $value
                }
            }
        }
    }
    return [join $retlist ,]
}

proc open_port {portname} {
    try {
        set result [mportlookup $portname]
        if {[llength $result] < 2} {
            ui_error "No such port: $portname"
            puts $::log_subports_progress "Building '$::portname' ... \[ERROR\] (unknown dependency '$portname') maintainers: [get_maintainers $::portname]."
            exit 1
        }
    } on error {eMessage} {
        ui_error "mportlookup $portname failed: $eMessage"
        exit 2
    }
    array set portinfo [lindex $result 1]
    try {
        set mport [mportopen $portinfo(porturl) [list subport $portinfo(name)] [list]]
    } on error {eMessage} {
        ui_error "mportopen $portinfo(porturl) failed: $eMessage"
        exit 2
    }

    if {![info exists ::mportinfo_array($mport)]} {
        set ::mportinfo_array($mport) [mportinfo $mport]
    }
    array set portinfo $::mportinfo_array($mport)
    return [list $mport [array get portinfo]]
}

proc deactivate_unneeded {portinfovar} {
    upvar $portinfovar portinfo

    # Unfortunately mportdepends doesn't have quite the right semantics
    # to be useful here. It's concerned with what is needed and not
    # present, whereas here we're concerned with removing what we can do
    # without. Future API opportunity?
    set deplist [list]
    foreach deptype $::toplevel_depstypes {
        if {[info exists portinfo($deptype)]} {
            foreach depspec $portinfo($deptype) {
                check_dep_needs_port $depspec deplist
            }
        }
    }
    while {$deplist ne ""} {
        set dep [lindex $deplist end]
        set deplist [lreplace ${deplist}[set deplist {}] end end]
        if {![info exists needed_array($dep)]} {
            set needed_array($dep) 1
            set needed [list]
            lassign [open_port $dep] mports_array($dep) infolist
            array unset depportinfo
            array set depportinfo $infolist
            collect_deps depportinfo needed
            foreach newdep $needed {
                if {![info exists needed_array($newdep)]} {
                    lappend deplist $newdep
                }
            }
        }
    }

    set dependents_check_list [list]
    puts "Deactivating unneeded ports:"
    foreach e [registry::entry installed] {
        # Deactivate everything we don't need and also ports we do need that
        # are active with an old version or non-default variants. The
        # latter will reduce performance for universal installations a
        # bit, but those are much less common and this ensures
        # consistent behaviour.
        if {![info exists needed_array([$e name])]} {
            if {![registry::run_target $e deactivate [list ports_force yes]]
                      && [catch {portimage::deactivate [$e name] [$e version] [$e revision] [$e variants] [list ports_force yes]} result]} {
                puts stderr $::errorInfo
                puts stderr "Deactivating [$e name] @[$e version]_[$e revision][$e variants] failed: $result"
                exit 2
            }
        } else {
            array unset entryinfo
            array set entryinfo $::mportinfo_array($mports_array([$e name]))
            if {$entryinfo(version) ne [$e version]
                    || $entryinfo(revision) != [$e revision]
                    || $entryinfo(canonical_active_variants) ne [$e variants]} {
                lappend dependents_check_list $e
                puts stderr "[$e name] installed version @[$e version]_[$e revision][$e variants] doesn't match tree version $entryinfo(version)_$entryinfo(revision)$entryinfo(canonical_active_variants)"
            }
        }
    }
    # also deactivate dependents of any needed deactivated ports
    if {$dependents_check_list ne ""} {
        puts "Deactivating ports with outdated versions/variants and their dependents:"
    }
    while {$dependents_check_list ne ""} {
        set e [lindex $dependents_check_list end]
        set dependents_check_list [lreplace ${dependents_check_list}[set dependents_check_list {}] end end]
        if {[$e state] eq "installed"} {
            lappend dependents_check_list {*}[$e dependents]
            if {![registry::run_target $e deactivate [list ports_force yes]]
                      && [catch {portimage::deactivate [$e name] [$e version] [$e revision] [$e variants] [list ports_force yes]} result]} {
                puts stderr $::errorInfo
                puts stderr "Deactivating [$e name] @[$e version]_[$e revision][$e variants] failed: $result"
                exit 2
            }
        }
    }
    # For ports that remain active, close the mport that was opened
    # earlier - it most likely won't be used again (and will be
    # reopened in the uncommon case that it is needed.)
    foreach e [registry::entry installed] {
        mportclose $mports_array([$e name])
    }
}

puts stderr "init took [expr {[clock seconds] - $start_time}] seconds"
set start_time [clock seconds]

if {[catch {deactivate_unneeded portinfo} result]} {
    ui_error $::errorInfo
    ui_error "deactivate_unneeded failed: $result"
    exit 2
}

puts stderr "deactivating unneeded ports took [expr {[clock seconds] - $start_time}] seconds"
set start_time [clock seconds]

# gather a list of dependencies with the correct variants (+universal is dealt
# with in specific ways)
if {[catch {mportdepends $mport "activate"} result]} {
    ui_error $::errorInfo
    ui_error "mportdepends $portname activate failed: $result"
    exit 2
} elseif {$result != 0} {
    ui_error "mportdepends $portname activate failed: $result"
    exit 2
}


proc append_it {ditem} {
    lappend ::dlist_sorted $ditem
    set ::mportinfo_array($ditem) [mportinfo $ditem]
    return 0
}
try {
    # sort these dependencies topologically; exclude the given port itself
    set dlist [dlist_append_dependents $macports::open_mports $mport {}]
    dlist_delete dlist $mport

    # produce a list of deps in sorted order
    set dlist_sorted [list]
    dlist_eval $dlist {} [list append_it]
    unset dlist
} on error {eMessage} {
    ui_error "sorting dlist failed: $eMessage"
    exit 2
}

puts stderr "calculating deps took [expr {[clock seconds] - $start_time}] seconds"
set start_time [clock seconds]

# print a message to two channels
proc tee {msg ch1 ch2} {
    puts $ch1 $msg
    puts $ch2 $msg
}

set dependencies_count [llength $dlist_sorted]
tee "Installing $dependencies_count dependencies of $portname:" $log_status_dependencies stdout
foreach ditem $dlist_sorted {
    tee "[ditem_key $ditem provides] [_mportkey $ditem PortInfo(canonical_active_variants)]" $log_status_dependencies stdout
}
puts $log_status_dependencies ""

## ensure dependencies are installed and active
proc checkdep_failcache {ditem} {
    array set depinfo $::mportinfo_array($ditem)

    if {[check_failcache $depinfo(name) [ditem_key $ditem porturl] $depinfo(canonical_active_variants)]} {
        tee "Dependency '$depinfo(name)' with variants '$depinfo(canonical_active_variants)' has previously failed and is required." $::log_status_dependencies stderr
        puts "Port $depinfo(name) previously failed in build [check_failcache $depinfo(name) [ditem_key $ditem porturl] $depinfo(canonical_active_variants) yes]"
        puts $::log_subports_progress "Building '$::portname' ... \[ERROR\] (failed to install dependency '$depinfo(name)') maintainers: [get_maintainers $::portname $depinfo(name)]."
        # could keep going to report all deps in the failcache, but failing fast seems better
        exit 1
    }
}

if {$failcache_dir ne ""} {
    try {
        foreach ditem $dlist_sorted {
            checkdep_failcache $ditem
        }
    } on error {eMessage} {
        ui_error "checkdep_failcache failed: $eMessage"
        exit 2
    }
    puts stderr "checking failcache took [expr {[clock seconds] - $start_time}] seconds"
    set start_time [clock seconds]
}

# Returns 0 if dep is installed, 1 if not
proc install_dep_archive {ditem} {
    array set depinfo $::mportinfo_array($ditem)
    incr ::dependencies_counter
    set msg "Installing dependency ($::dependencies_counter of $::dependencies_count) '$depinfo(name)' with variants '$depinfo(canonical_active_variants)'"
    puts -nonewline $::log_status_dependencies "$msg ... "
    puts "----> ${msg}"
    if {[registry::entry imaged $depinfo(name) $depinfo(version) $depinfo(revision) $depinfo(canonical_active_variants)] ne ""} {
        puts "Already installed, nothing to do"
        puts $::log_status_dependencies {[OK]}
        return 0
    }
    # clean up any work directories left over from earlier
    # (avoids possible errors with different variants in the statefile)
    set build_dir [file join $macports::portdbpath build]
    foreach dir [glob -nocomplain -directory $build_dir *] {
        file delete -force -- $dir
    }
    set fail 0
    set workername [ditem_key $ditem workername]

    # First fetch the archive
    if {[catch {mportexec $ditem archivefetch} result]} {
        puts stderr $::errorInfo
        ui_error "Archivefetch failed: $result"
        set fail 1
    }
    if {$fail || $result > 0 || [$workername eval [list find_portarchive_path]] eq ""} {
        # The known_fail case should normally be caught before now, but
        # it's quick and easy to check and may save a build.
        if {[info exists depinfo(known_fail)] && [string is true -strict $depinfo(known_fail)]} {
            puts stderr "Dependency '$depinfo(name)' with variants '$depinfo(canonical_active_variants)' is known to fail, aborting."
            puts $::log_status_dependencies {[FAIL] (known_fail)}
            puts $::log_subports_progress "Building '$::portname' ... \[ERROR\] (dependency '$depinfo(name)' known to fail) maintainers: [get_maintainers $::portname $depinfo(name)]."
            exit 1
        }
        # This dep will have to be built, not just installed
        puts stderr "Fetching archive for dependency '$depinfo(name)' with variants '$depinfo(canonical_active_variants)' failed."
        puts $::log_status_dependencies {[MISSING]}
        return 1
    }
    # Now install it
    if {[catch {$workername eval [list eval_targets install]} result]} {
        puts stderr $::errorInfo
        ui_error "Install failed: $result"
        set fail 1
    }
    if {$fail || $result > 0} {
        puts stderr "Installing from archive for dependency '$depinfo(name)' with variants '$depinfo(canonical_active_variants)' failed, aborting."
        puts $::log_status_dependencies {[FAIL]}
        puts $::log_subports_progress "Building '$::portname' ... \[ERROR\] (failed to install dependency '$depinfo(name)')."
        exit 1
    }

    puts $::log_status_dependencies {[OK]}
    return 0
}

# mportexec uses this global variable, so we have to clean up between
# doing operations (that require deps) on different ports.
proc close_open_mports {} {
    foreach mport $macports::open_mports {
        catch {mportclose $mport}
    }
}

proc install_dep_source {portinfo_list} {
    array set depinfo $portinfo_list
    incr ::build_counter
    set msg "Building dependency ($::build_counter of $::build_count) '$depinfo(name)' with variants '$depinfo(canonical_active_variants)'"
    puts -nonewline $::log_status_dependencies "$msg ... "
    puts "----> ${msg}"
    close_open_mports
    array unset ::mportinfo_array
    set ditem [lindex [open_port $depinfo(name)] 0]

    # deactivate ports not needed for this dep
    if {[catch {deactivate_unneeded depinfo} result]} {
        ui_error $::errorInfo
        ui_error "deactivate_unneeded failed: $result"
        exit 2
    }

    # Fetch and checksum the distfiles
    if {[catch {mportexec $ditem fetch} result]} {
        puts stderr $::errorInfo
        ui_error "Fetch failed: $result"
        set fail 1
    }
    if {$fail || $result > 0} {
        puts stderr "Fetch of dependency '$depinfo(name)' with variants '$depinfo(canonical_active_variants)' failed, aborting."
        puts $::log_status_dependencies {[FAIL] (fetch)}
        puts $::log_subports_progress "Building '$::portname' ... \[ERROR\] (failed to fetch dependency '$depinfo(name)') maintainers: [get_maintainers $::portname $depinfo(name)]."
        exit 1
    }
    if {[catch {mportexec $ditem checksum} result]} {
        puts stderr $::errorInfo
        ui_error "Checksum failed: $result"
        set fail 1
    }
    if {$fail || $result > 0} {
        puts stderr "Checksum of dependency '$depinfo(name)' with variants '$depinfo(canonical_active_variants)' failed, aborting."
        puts $::log_status_dependencies {[FAIL] (checksum)}
        puts $::log_subports_progress "Building '$::portname' ... \[ERROR\] (failed to checksum dependency '$depinfo(name)') maintainers: [get_maintainers $::portname $depinfo(name)]."
        exit 1
    }

    # Now install
    if {[catch {mportexec $ditem install} result]} {
        puts stderr $::errorInfo
        ui_error "Install failed: $result"
        set fail 1
    }
    if {$fail || $result > 0} {
        puts stderr "Build of dependency '$depinfo(name)' with variants '$depinfo(canonical_active_variants)' failed, aborting."
        puts $::log_status_dependencies {[FAIL]}
        puts $::log_subports_progress "Building '$::portname' ... \[ERROR\] (failed to install dependency '$depinfo(name)') maintainers: [get_maintainers $::portname $depinfo(name)]."

        if {$::failcache_dir ne ""} {
            failcache_update $depinfo(name) [ditem_key $ditem porturl] $depinfo(canonical_active_variants) 1
        }
        exit 1
    }

    # Success. Clear any failcache entry.
    if {$::failcache_dir ne ""} {
        failcache_update $depinfo(name) [ditem_key $ditem porturl] $depinfo(canonical_active_variants) 0
    }
    puts $::log_status_dependencies {[OK]}
}

# Show all output for anything that gets installed
set macports::channels(debug) stderr
set macports::channels(info) stdout
set dependencies_counter 0
set missing_deps [list]
try {
    foreach ditem $dlist_sorted {
        if {[install_dep $ditem]} {
            lappend missing_deps $::mportinfo_array($ditem)
        }
    }
} on error {eMessage} {
    ui_error "install_dep failed: $eMessage"
    exit 2
}

puts stderr "installing deps took [expr {[clock seconds] - $start_time}] seconds"
set start_time [clock seconds]

set build_count [llength $missing_deps]
if {$build_count > 0} {
    # Some deps are neither installed nor able to be fetched as an archive.
    # This should ideally never happen since each dep should have had
    # its own build previously, but failures and out-of-order builds
    # do happen sometimes for various reasons.
    tee "Building $build_count dependencies of $portname:" $log_status_dependencies stdout
    set build_counter 0
    foreach missing_dep $missing_deps {
        install_dep_source $missing_dep
    }

    puts stderr "building missing deps took [expr {[clock seconds] - $start_time}] seconds"
    set start_time [clock seconds]

    # Now effectively start again for the main port.
    close_open_mports
    array unset ::mportinfo_array
    try {
        set mport [mportopen $portinfo(porturl) [list subport $portinfo(name)] [array get variants]]
    } on error {eMessage} {
        ui_error "mportopen $portinfo(porturl) failed: $eMessage"
        exit 2
    }
    [ditem_key $mport workername] eval [list set portutil::archive_available_result 0]
    if {[catch {deactivate_unneeded portinfo} result]} {
        ui_error $::errorInfo
        ui_error "deactivate_unneeded failed: $result"
        exit 2
    }

    puts stderr "deactivating unneeded ports (again) took [expr {[clock seconds] - $start_time}] seconds"
    set start_time [clock seconds]

    # gather a list of dependencies with the correct variants (+universal is dealt
    # with in specific ways)
    if {[catch {mportdepends $mport "activate"} result]} {
        ui_error $::errorInfo
        ui_error "mportdepends $portname activate failed: $result"
        exit 2
    } elseif {$result != 0} {
        ui_error "mportdepends $portname activate failed: $result"
        exit 2
    }

   try {
        # sort these dependencies topologically; exclude the given port itself
        set dlist [dlist_append_dependents $macports::open_mports $mport {}]
        dlist_delete dlist $mport

        # produce a list of deps in sorted order
        set dlist_sorted [list]
        dlist_eval $dlist {} [list append_it]
        unset dlist
    } on error {eMessage} {
        ui_error "sorting dlist failed: $eMessage"
        exit 2
    }

    puts stderr "calculating deps (again) took [expr {[clock seconds] - $start_time}] seconds"
    set start_time [clock seconds]
}

# Go back to being quiet
set macports::channels(debug) {}
set macports::channels(info) {}

proc activate_dep {ditem} {
    set workername [ditem_key $ditem workername]
    set fail 0
    if {[catch {$workername eval [list eval_targets activate]} result]} {
        puts stderr $::errorInfo
        ui_error "Activate failed: $result"
        set fail 1
    }
    if {$fail || $result > 0} {
        array set depinfo $::mportinfo_array($ditem)
        puts stderr "Activation of dependency '$depinfo(name)' with variants '$depinfo(canonical_active_variants)' failed, aborting."
        puts $::log_subports_progress "Building '$::portname' ... \[ERROR\] (failed to activate dependency '$depinfo(name)') maintainers: [get_maintainers $::portname $depinfo(name)]."
        exit 1
    }
}

puts "Activating all dependencies..."
try {
    foreach ditem $dlist_sorted {
        activate_dep $ditem
    }
} on error {eMessage} {
    ui_error "activate_dep failed: $eMessage"
    exit 2
}

puts stderr "activating deps took [expr {[clock seconds] - $start_time}] seconds"

puts "Done."
exit 0
