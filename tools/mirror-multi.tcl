#!/usr/bin/env port-tclsh
# -*- coding: utf-8; mode: tcl; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- vim:fenc=utf-8:ft=tcl:et:sw=4:ts=4:sts=4
#
# Mirrors the distfiles for the given ports, for each possible variant
# and supported platform. Skips those that have already been mirrored
# by comparing the Portfile's hash against the hash recorded previously.
#
# Copyright (c) 2018 The MacPorts Project.
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

package require macports
package require fetch_common

source [file join [file dirname [info script]] mirrordb.tcl]

set ui_options(ports_verbose) yes
if {[catch {mportinit ui_options "" ""} result]} {
   ui_error "$errorInfo"
   ui_error "Failed to initialize ports system: $result"
   exit 1
}

set platforms [list 9 powerpc 9 i386]
foreach vers {10 11 12 13 14 15 16 17 18 19} {
    if {${macports::os_major} != $vers} {
        lappend platforms $vers i386
    }
}
foreach vers {20 21 22 23 24 25} {
    if {${macports::os_major} != $vers} {
        lappend platforms $vers arm $vers i386
    } elseif {${macports::os_arch} eq "i386"} {
        lappend platforms $vers arm
    } else {
        lappend platforms $vers i386
    }
}
set deptypes [list depends_fetch depends_extract depends_patch depends_build depends_lib depends_run depends_test]

set processed [dict create]
set mirror_done [dict create]
set distfiles_results [dict create]

proc check_mirror_done_local {portname} {
    global mirror_done
    if {[dict exists $mirror_done $portname]} {
        return [dict get $mirror_done $portname]
    }
    global mirrorcache_dir
    set cache_entry [file join $mirrorcache_dir [string toupper [string index $portname 0]] $portname]
    if {[file isfile $cache_entry]} {
        set portfile_hash [get_portfile_hash $portname]
        if {$portfile_hash eq {}} {
            return 0
        }
        set fd [open $cache_entry]
        set entry_hash [gets $fd]
        set partial [gets $fd]
        close $fd
        if {$portfile_hash eq $entry_hash} {
            if {$partial eq ""} {
                dict set mirror_done $portname 1
                return 1
            } else {
                dict set mirror_done $portname $partial
                return $partial
            }
        } else {
            file delete -force $cache_entry
            dict set mirror_done $portname 0
        }
    } else {
        dict set mirror_done $portname 0
    }
    return 0
}

proc check_mirror_done_remote {portname} {
    global mirror_done
    if {[dict exists $mirror_done $portname]} {
        return [dict get $mirror_done $portname]
    }
    set db_hash [get_remote_db_value mirror.sha256.${portname}]
    if {$db_hash eq [get_portfile_hash $portname]} {
        set result [get_remote_db_value mirror.status.${portname}]
        if {$result ne {}} {
            dict set mirror_done $portname $result
            return $result
        }
        ui_warn "Failed to retrieve mirrored status for ${portname}."
    } else {
        if {$db_hash eq {}} {
            ui_msg "$portname does not appear to have been mirrored before."
        } else {
            ui_msg "$portname has changed since it was last mirrored."
        }
        dict set mirror_done $portname 0
    }
    return 0
}


proc set_mirror_done_remote {portname value} {
    # We actually need to upload the files before updating their
    # status in the remote db, so just update the dict here.
    global mirror_done
    if {![dict exists $mirror_done $portname] || [dict get $mirror_done $portname] != 1} {
        dict set mirror_done $portname $value
    }
}

# Write out info needed to update the remote db.
proc write_status_dicts {} {
    foreach d {mirror_done portfile_hash_cache portname_portfile_map} {
        global $d
        set fd [open $d w]
        puts -nonewline $fd [set $d]
        close $fd
    }
}


proc set_mirror_done_local {portname value} {
    global mirror_done
    if {![dict exists $mirror_done $portname] || [dict get $mirror_done $portname] != 1} {
        global mirrorcache_dir
        set portfile_hash [get_portfile_hash $portname]

        set cache_dir [file join $mirrorcache_dir [string toupper [string index $portname 0]]]
        file mkdir $cache_dir
        set cache_entry [file join $cache_dir $portname]
        set fd [open $cache_entry w]
        puts $fd $portfile_hash
        if {$value != 1} {
            puts $fd $value
        }
        close $fd
        dict set mirror_done $portname 1
    }
}

proc get_dep_list {portinfo} {
    global deptypes
    set deps [dict create]
    foreach deptype $deptypes {
        if {[dict exists $portinfo $deptype]} {
            foreach dep [dict get $portinfo $deptype] {
                dict set deps [lindex [split $dep :] end] 1
            }
        }
    }
    return $deps
}

proc get_variants {portinfo} {
    if {![dict exists $portinfo vinfo]} {
        return {}
    }
    set variants {}
    dict for {vname variant} [dict get $portinfo vinfo] {
        if {![dict exists $variant is_default] || [dict get $variant is_default] ne "+"} {
            lappend variants $vname
        }
    }
    return $variants
}

# Remember that the distfiles have been tried already
# (same distfiles can be shared by multiple ports)
proc save_distfiles_results {mport succeeded} {
    if {[catch {_mportkey $mport all_dist_files} all_dist_files]} {
        # no distfiles, no problem
        return
    }
    global distfiles_results
    set distpath [_mportkey $mport distpath]
    foreach distfile $all_dist_files {
        set filepath [file join $distpath $distfile]
        dict set distfiles_results $filepath $succeeded
    }
}

# Given a distribution file name, return the name without an attached tag
# Example : getdistname distfile.tar.gz:tag1 returns "distfile.tar.gz"
# / isn't included in the regexp, thus allowing port specification in URLs.
proc getdistname {name} {
    regexp {(.+):[0-9A-Za-z_-]+$} $name match name
    return $name
}

# check if mirroring should be skipped due to all distfiles having
# previously been successfully mirrored, or any distfile previously
# having a checksum mismatch
# Returns:
# 0 - mirror needed
# 1 - mirror not needed
# 2 - mirror already failed for at least one distfile
proc skip_mirror {mport identifier} {
    if {([catch {_mportkey $mport distfiles} distfiles] || $distfiles eq "")
        && ([catch {_mportkey $mport patchfiles} patchfiles] || $patchfiles eq "")} {
        # no distfiles, no need to mirror
        return 1
    }
    global distfiles_results check_distfiles_url
    if {![info exists distfiles]} {
        set distfiles [list]
    }
    if {![info exists patchfiles]} {
        set patchfiles [list]
    }
    if {$check_distfiles_url} {
        set dist_subdir [_mportkey $mport dist_subdir]
        global distfiles_url distfiles_url_results
    }
    set distpath [_mportkey $mport distpath]
    set filespath [_mportkey $mport filespath]
    set any_unmirrored 0
    foreach distfile [concat $distfiles $patchfiles] {
        if {[file exists [file join $filespath $distfile]]} {
            continue
        }
        set distfile [getdistname $distfile]
        if {$check_distfiles_url} {
            if {[dict exists $distfiles_url_results ${dist_subdir}/${distfile}]} {
                set url_result [dict get $distfiles_url_results ${dist_subdir}/${distfile}]
            } else {
                set distfile_url ${distfiles_url}${dist_subdir}/[portfetch::percent_encode $distfile]
                set url_result [expr {![catch {curl getsize $distfile_url} size] && $size > 0}]
                dict set distfiles_url_results ${dist_subdir}/${distfile} $url_result
            }
            if {$url_result} {
                continue
            }
        }
        set filepath [file join $distpath $distfile]
        if {![dict exists $distfiles_results $filepath]} {
            set any_unmirrored 1
        } elseif {[dict get $distfiles_results $filepath] == 0} {
            ui_msg "Skipping ${identifier}: $distfile already failed checksum"
            return 2
        }
    }
    if {$any_unmirrored == 0} {
        #ui_msg "Skipping ${identifier}: all distfiles already mirrored"
        return 1
    }
    return 0
}


proc mirror_port {portinfo} {
    global processed platforms
    set portname [dict get $portinfo name]
    set porturl [dict get $portinfo porturl]
    dict set processed $portname 1
    set do_mirror 1
    set attempted 0
    set succeeded 0
    if {[lsearch -exact -nocase [dict get $portinfo license] "nomirror"] >= 0} {
        ui_msg "Not mirroring $portname due to license"
        set do_mirror 0
    }
    if {[catch {mportopen $porturl [dict create subport $portname] {}} mport]} {
        ui_error "mportopen $porturl failed: $mport"
        return 1
    }
    set portinfo [mportinfo $mport]

    set skip_result [skip_mirror $mport $portname]
    if {$do_mirror && $skip_result == 0} {
        incr attempted
        mportexec $mport clean
        if {[mportexec $mport mirror] == 0} {
            save_distfiles_results $mport 1
            incr succeeded
        } else {
            save_distfiles_results $mport 0
        }
    } elseif {$skip_result == 2} {
        # count as a failure
        incr attempted
    }
    mportclose $mport

    set deps [get_dep_list $portinfo]
    set variants [get_variants $portinfo]

    foreach variant $variants {
        ui_msg "$portname +${variant}"
        if {[catch {mportopen $porturl [dict create subport $portname] [dict create $variant +]} mport]} {
            ui_error "mportopen $porturl failed: $mport"
            continue
        }
        set portinfo [mportinfo $mport]
        set deps [dict merge [get_dep_list $portinfo] $deps]
        set skip_result [skip_mirror $mport "$portname +${variant}"]
        if {$do_mirror && $skip_result == 0} {
            incr attempted
            mportexec $mport clean
            if {[mportexec $mport mirror] == 0} {
                save_distfiles_results $mport 1
                incr succeeded
            } else {
                save_distfiles_results $mport 0
            }
        } elseif {$skip_result == 2} {
            incr attempted
        }
        mportclose $mport
    }

    foreach {os_major os_arch} $platforms {
        ui_msg "$portname with platform 'darwin $os_major $os_arch'"
        if {[catch {mportopen $porturl [dict create subport $portname os_major $os_major os_arch $os_arch] {}} mport]} {
            ui_error "mportopen $porturl failed: $mport"
            continue
        }
        set portinfo [mportinfo $mport]
        set deps [dict merge [get_dep_list $portinfo] $deps]
        set skip_result [skip_mirror $mport "$portname darwin $os_major $os_arch"]
        if {$do_mirror && $skip_result == 0} {
            incr attempted
            mportexec $mport clean
            if {[mportexec $mport mirror] == 0} {
                save_distfiles_results $mport 1
                incr succeeded
            } else {
                save_distfiles_results $mport 0
            }
        } elseif {$skip_result == 2} {
            incr attempted
        }
        mportclose $mport
    }

    set dep_failed 0
    foreach dep [dict keys $deps] {
        if {![dict exists $processed $dep] && [check_mirror_done $dep] == 0} {
            set result [mportlookup $dep]
            if {[llength $result] < 2} {
                ui_error "No such port: $dep"
                set dep_failed 1
                continue
            }
            if {[mirror_port [lindex $result 1]] != 0} {
                set dep_failed 1
            }
        }
    }

    if {$dep_failed == 0 && ($attempted == 0 || $succeeded > 0)} {
        if {$succeeded == $attempted} {
            set_mirror_done $portname 1
        } else {
            set_mirror_done $portname 0.5
        }
        return 0
    }
    return 1
}

set mirrorcache_dir /tmp/mirrorcache
set use_cachedir yes
set include_subports no
set use_remotedb no
set check_distfiles_url no
while {[string match -* [lindex $argv 0]]} {
    switch -- [lindex $argv 0] {
        -c {
            set use_cachedir yes
            set mirrorcache_dir [lindex $argv 1]
            set argv [lrange $argv 1 end]
        }
        -d {
            set check_distfiles_url yes
            set distfiles_url_results [dict create]
            set distfiles_url [lindex $argv 1]
            set argv [lrange $argv 1 end]
        }
        -s {
            set include_subports yes
        }
        -r {
            set use_remotedb yes
            set use_cachedir no
            set mirrorcache_baseurl [lindex $argv 1]
            set mirrorcache_credentials [lindex $argv 2]
            set argv [lrange $argv 2 end]
        }
        default {
            ui_error "Unknown option [lindex $argv 0]"
        }
    }
    set argv [lrange $argv 1 end]
}
if {$use_cachedir} {
    rename check_mirror_done_local check_mirror_done
    rename set_mirror_done_local set_mirror_done
} elseif {$use_remotedb} {
    rename check_mirror_done_remote check_mirror_done
    rename set_mirror_done_remote set_mirror_done
}

proc process_port {portname} {
    global processed
    if {[dict exists $processed $portname]} {
        ui_msg "skipping ${portname}, already processed"
        return
    }
    if {[check_mirror_done $portname] == 1} {
        ui_msg "skipping ${portname}, previously mirrored"
        return
    }

    global exitval
    set result [mportlookup $portname]
    if {[llength $result] < 2} {
        ui_error "No such port: $portname"
        set exitval 1
        return
    }
    set portinfo [lindex $result 1]
    if {[mirror_port $portinfo] != 0} {
        set exitval 1
    }

    global include_subports
    if {$include_subports} {
        set subports [expr {[dict exists $portinfo subports] ? [dict get $portinfo subports] : {}}]
        foreach subport $subports {
            process_port $subport
        }
    }
}

set exitval 0
foreach portname $argv {
    process_port $portname
}

if {$use_remotedb} {
    write_status_dicts
}

exit $exitval
