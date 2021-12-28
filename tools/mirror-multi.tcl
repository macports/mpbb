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

if {[catch {mportinit "" "" ""} result]} {
   ui_error "$errorInfo"
   ui_error "Failed to initialize ports system: $result"
   exit 1
}

set platforms [list 8 powerpc 8 i386 9 powerpc 9 i386]
foreach vers {10 11 12 13 14 15 16 17 18 19} {
    if {${macports::os_major} != $vers} {
        lappend platforms $vers i386
    }
}
foreach vers {20 21} {
    if {${macports::os_major} != $vers} {
        lappend platforms $vers arm $vers i386
    }
}
set deptypes {depends_fetch depends_extract depends_build depends_lib depends_run depends_test}

array set processed [list]
array set mirror_done [list]
array set distfiles_results [list]

proc check_mirror_done {portname} {
    global mirror_done mirrorcache_dir
    if {[info exists mirror_done($portname)]} {
        return $mirror_done($portname)
    }
    set cache_entry [file join $mirrorcache_dir [string toupper [string index $portname 0]] $portname]
    if {[file isfile $cache_entry]} {
        set result [mportlookup $portname]
        if {[llength $result] < 2} {
            return 0
        }
        array unset portinfo
        array set portinfo [lindex $result 1]
        set portfile [file join [macports::getportdir $portinfo(porturl)] Portfile]
        if {[file isfile $portfile]} {
            set portfile_hash [sha256 file $portfile]
            set fd [open $cache_entry]
            set entry_hash [gets $fd]
            set partial [gets $fd]
            close $fd
            if {$portfile_hash eq $entry_hash} {
                if {$partial eq ""} {
                    set mirror_done($portname) 1
                    return 1
                } else {
                    set mirror_done($portname) $partial
                    return $partial
                }
            } else {
                file delete -force $cache_entry
                set mirror_done($portname) 0
            }
        }
    } else {
        set mirror_done($portname) 0
    }
    return 0
}

proc set_mirror_done {portname value} {
    global mirror_done mirrorcache_dir
    if {![info exists mirror_done($portname)] || $mirror_done($portname) != 1} {
        set result [mportlookup $portname]
        array unset portinfo
        array set portinfo [lindex $result 1]
        set portfile [file join [macports::getportdir $portinfo(porturl)] Portfile]
        set portfile_hash [sha256 file $portfile]

        set cache_dir [file join $mirrorcache_dir [string toupper [string index $portname 0]]]
        file mkdir $cache_dir
        set cache_entry [file join $cache_dir $portname]
        set fd [open $cache_entry w]
        puts $fd $portfile_hash
        if {$value != 1} {
            puts $fd $value
        }
        close $fd
        set mirror_done($portname) 1
    }
}

proc get_dep_list {portinfovar} {
    global deptypes
    upvar $portinfovar portinfo
    set deps {}
    foreach deptype $deptypes {
        if {[info exists portinfo($deptype)]} {
            foreach dep $portinfo($deptype) {
                lappend deps [lindex [split $dep :] end]
            }
        }
    }
    return $deps
}

proc get_variants {portinfovar} {
    upvar $portinfovar portinfo
    if {![info exists portinfo(vinfo)]} {
        return {}
    }
    set variants {}
    array set vinfo $portinfo(vinfo)
    foreach v [array names vinfo] {
        array unset variant
        array set variant $vinfo($v)
        if {![info exists variant(is_default)] || $variant(is_default) ne "+"} {
            lappend variants $v
        }
    }
    return $variants
}

# work around the bug where the mirror target claims to succeed when
# the distfile checksums did not match
proc check_distfiles {mport} {
    global distfiles_results
    if {[catch {_mportkey $mport all_dist_files} all_dist_files]} {
        # no distfiles, no problem
        return 0
    }
    set distpath [_mportkey $mport distpath]
    set ret 0
    foreach distfile $all_dist_files {
        set filepath [file join $distpath $distfile]
        if {[file exists $filepath]} {
            set distfiles_results($filepath) 1
        } else {
            set distfiles_results($filepath) 0
            set ret 1
        }
    }
    return $ret
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
    if {![info exists distfiles]} {
        set distfiles [list]
    }
    if {![info exists patchfiles]} {
        set patchfiles [list]
    }
    global distfiles_results
    set distpath [_mportkey $mport distpath]
    set filespath [_mportkey $mport filespath]
    set any_unmirrored 0
    foreach distfile [concat $distfiles $patchfiles] {
        if {[file exists [file join $filespath $distfile]]} {
            continue
        }
        set distfile [getdistname $distfile]
        set filepath [file join $distpath $distfile]
        if {![info exists distfiles_results($filepath)]} {
            set any_unmirrored 1
        } elseif {$distfiles_results($filepath) == 0} {
            ui_msg "Skipping ${identifier}: $distfile already failed checksum"
            return 2
        }
    }
    if {$any_unmirrored == 0} {
        ui_msg "Skipping ${identifier}: all distfiles already mirrored"
        return 1
    }
    return 0
}


proc mirror_port {portinfo_list} {
    global platforms deptypes processed

    array set portinfo $portinfo_list
    set portname $portinfo(name)
    set porturl $portinfo(porturl)
    set processed($portname) 1
    set do_mirror 1
    set attempted 0
    set succeeded 0
    if {[lsearch -exact -nocase $portinfo(license) "nomirror"] >= 0} {
        ui_msg "Not mirroring $portname due to license"
        set do_mirror 0
    }
    if {[catch {mportopen $porturl [list subport $portname] {}} mport]} {
        ui_error "mportopen $porturl failed: $mport"
        return 1
    }
    array unset portinfo
    array set portinfo [mportinfo $mport]

    set skip_result [skip_mirror $mport $portname]
    if {$do_mirror && $skip_result == 0} {
        incr attempted
        mportexec $mport clean
        if {[mportexec $mport mirror] == 0 && [check_distfiles $mport] == 0} {
            incr succeeded
        }
    } elseif {$skip_result == 2} {
        # count as a failure
        incr attempted
    }
    mportclose $mport

    set deps [get_dep_list portinfo]
    set variants [get_variants portinfo]

    foreach variant $variants {
        ui_msg "$portname +${variant}"
        if {[catch {mportopen $porturl [list subport $portname] [list $variant +]} mport]} {
            ui_error "mportopen $porturl failed: $mport"
            continue
        }
        array unset portinfo
        array set portinfo [mportinfo $mport]
        lappend deps {*}[get_dep_list portinfo]
        set skip_result [skip_mirror $mport "$portname +${variant}"]
        if {$do_mirror && $skip_result == 0} {
            incr attempted
            mportexec $mport clean
            if {[mportexec $mport mirror] == 0  && [check_distfiles $mport] == 0} {
                incr succeeded
            }
        } elseif {$skip_result == 2} {
            incr attempted
        }
        mportclose $mport
    }

    foreach {os_major os_arch} $platforms {
        ui_msg "$portname with platform 'darwin $os_major $os_arch'"
        if {[catch {mportopen $porturl [list subport $portname os_major $os_major os_arch $os_arch] {}} mport]} {
            ui_error "mportopen $porturl failed: $mport"
            continue
        }
        array unset portinfo
        array set portinfo [mportinfo $mport]
        lappend deps {*}[get_dep_list portinfo]
        set skip_result [skip_mirror $mport "$portname darwin $os_major $os_arch"]
        if {$do_mirror && $skip_result == 0} {
            incr attempted
            mportexec $mport clean
            if {[mportexec $mport mirror] == 0 && [check_distfiles $mport] == 0} {
                incr succeeded
            }
        } elseif {$skip_result == 2} {
            incr attempted
        }
        mportclose $mport
    }

    set dep_failed 0
    foreach dep [lsort -unique $deps] {
        if {![info exists processed($dep)] && [check_mirror_done $dep] == 0} {
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
if {[lindex $::argv 0] eq "-c"} {
    set mirrorcache_dir [lindex $::argv 1]
    set ::argv [lrange $::argv 2 end]
}

set exitval 0
foreach portname $::argv {
    if {[info exists processed($portname)]} {
        ui_msg "skipping ${portname}, already processed"
        continue
    }
    if {[check_mirror_done $portname] == 1} {
        ui_msg "skipping ${portname}, previously mirrored"
        continue
    }

    set result [mportlookup $portname]
    if {[llength $result] < 2} {
        ui_error "No such port: $portname"
        set exitval 1
        continue
    }
    if {[mirror_port [lindex $result 1]] != 0} {
        set exitval 1
    }
}

exit $exitval
