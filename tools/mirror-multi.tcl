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
foreach vers {10 11 12 13 14 15 16 17} {
    if {${macports::os_major} != $vers} {
        lappend platforms $vers i386
    }
}
set deptypes {depends_fetch depends_extract depends_build depends_lib depends_run depends_test}

array set tried_and_failed {}
array set mirror_done {}

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
            close $fd
            if {$portfile_hash eq $entry_hash} {
                set mirror_done($portname) 1
                return 1
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

proc set_mirror_done {portname} {
    global mirror_done mirrorcache_dir
    if {![info exists mirror_done($portname)] || $mirror_done($portname) == 0} {
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

proc mirror_port {portinfo_list} {
    global platforms deptypes tried_and_failed

    array set portinfo $portinfo_list
    set portname $portinfo(name)
    set porturl $portinfo(porturl)
    set do_mirror 1
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
    set any_failed 0
    # have to checksum too since the mirror target claims to succeed
    # even if the checksums were wrong and the files deleted
    if {$do_mirror && ([mportexec $mport mirror] != 0 || [mportexec $mport checksum] != 0)} {
        set any_failed 1
        set tried_and_failed($portname) 1
    }
    mportclose $mport

    set deps [get_dep_list portinfo]
    set variants [get_variants portinfo]

    foreach variant $variants {
        ui_msg "$portname +${variant}"
        if {[catch {mportopen $porturl [list subport $portname] [list $variant +]} mport]} {
            ui_error "mportopen $porturl failed: $mport"
            set any_failed 1
            set tried_and_failed($portname) 1
            continue
        }
        array unset portinfo
        array set portinfo [mportinfo $mport]
        lappend deps {*}[get_dep_list portinfo]
        if {$do_mirror && ([mportexec $mport mirror] != 0  || [mportexec $mport checksum] != 0)} {
            set any_failed 1
        }
        mportclose $mport
    }

    foreach {os_major os_arch} $platforms {
        ui_msg "$portname with platform 'darwin $os_major $os_arch'"
        if {[catch {mportopen $porturl [list subport $portname os_major $os_major os_arch $os_arch] {}} mport]} {
            ui_error "mportopen $porturl failed: $mport"
            set any_failed 1
            set tried_and_failed($portname) 1
            continue
        }
        array unset portinfo
        array set portinfo [mportinfo $mport]
        lappend deps {*}[get_dep_list portinfo]
        if {$do_mirror && ([mportexec $mport mirror] != 0 || [mportexec $mport checksum] != 0)} {
            set any_failed 1
        }
        mportclose $mport
    }

    foreach dep [lsort -unique $deps] {
        if {![info exists tried_and_failed($dep)] && ![check_mirror_done $dep]} {
            set result [mportlookup $dep]
            if {[llength $result] < 2} {
                ui_error "No such port: $dep"
                set any_failed 1
                continue
            }
            if {[mirror_port [lindex $result 1]] != 0} {
                set any_failed 1
            }
        }
    }

    if {$any_failed == 0} {
        set_mirror_done $portname
    }
    return $any_failed
}

set mirrorcache_dir /tmp/mirrorcache
if {[lindex $::argv 0] eq "-c"} {
    set mirrorcache_dir [lindex $::argv 1]
    set ::argv [lrange $::argv 2 end]
}

set exitval 0
foreach portname $::argv {
    if {[info exists tried_and_failed($portname)]} {
        ui_msg "skipping ${portname}, already tried and failed"
        continue
    }
    if {[check_mirror_done $portname]} {
        ui_msg "skipping ${portname}, already mirrored"
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
