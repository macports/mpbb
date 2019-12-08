#!/usr/bin/env port-tclsh
#
# Generates a list of ports where a port is only listed after all of its
# dependencies (sans variants) have already been listed. Includes all
# sub-ports of the specified ports.
#
# Copyright (c) 2006,2008 Bryan L Blackburn.  All rights reserved.
# Copyright (c) 2018-2019 The MacPorts Project
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
# 3. Neither the name Bryan L Blackburn, nor the names of any contributors
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
#

package require macports


proc ui_prefix {priority} {
   return "OUT: "
}


proc ui_channels {priority} {
   return {}
}


proc process_port_deps {portname portdeps_in portlist_in} {
    upvar $portdeps_in portdeps
    upvar $portlist_in portlist
    set deplist $portdeps($portname)
    unset portdeps($portname)
    foreach portdep $deplist {
        if {[info exists portdeps($portdep)]} {
            process_port_deps $portdep portdeps portlist
        }
    }
    lappend portlist $portname
}


if {[catch {mportinit "" "" ""} result]} {
   puts stderr "$errorInfo"
   error "Failed to initialize ports system: $result"
}

set archive_site_private ""
set archive_site_public ""
set jobs_dir ""
set license_db_dir ""
while {[string range [lindex $::argv 0] 0 1] eq "--"} {
    switch -- [lindex $::argv 0] {
        --archive_site_private {
            set archive_site_private [lindex $::argv 1]
            set ::argv [lrange $::argv 1 end]
        }
        --archive_site_public {
            set archive_site_public [lindex $::argv 1]
            set ::argv [lrange $::argv 1 end]
        }
        --jobs_dir {
            set jobs_dir [lindex $::argv 1]
            set ::argv [lrange $::argv 1 end]
        }
        --license_db_dir {
            set license_db_dir [lindex $::argv 1]
            set ::argv [lrange $::argv 1 end]
        }
        default {
            error "unknown option: [lindex $::argv 0]"
        }
    }
    set ::argv [lrange $::argv 1 end]
}

if {$jobs_dir ne "" && $archive_site_public ne "" && $archive_site_private ne ""} {
    source ${jobs_dir}/distributable_lib.tcl
    if {$license_db_dir ne ""} {
        init_license_db $license_db_dir
    }
}

set is_64bit_capable [sysctl hw.cpu64bit_capable]

array set portdepinfo {}
array set canonicalnames {}
set todo [list]
if {[lindex $argv 0] eq "-"} {
    while {[gets stdin line] >= 0} {
        lappend todo [string tolower [string trim $line]]
    }
} else {
    foreach p $argv {
        lappend todo [string tolower $p]
    }
}
# save the ones that the user actually wants to know about
foreach p $todo {
    set inputports($p) 1
    set outputports($p) 1
}
# process all recursive deps
set depstypes {depends_fetch depends_extract depends_patch depends_build depends_lib depends_run}
while {$todo ne {}} {
    set p [lindex $todo 0]
    set todo [lrange $todo 1 end]

    if {![info exists portdepinfo($p)]} {
        if {[catch {mportlookup $p} result]} {
            puts stderr "$errorInfo"
            error "Failed to find port '$p': $result"
        }
        if {[llength $result] < 2} {
            puts stderr "port $p not found in the index"
            continue
        }

        array set portinfo [lindex $result 1]

        if {[info exists inputports($p)] && [info exists portinfo(subports)]} {
            foreach subport $portinfo(subports) {
                set splower [string tolower $subport]
                if {![info exists portdepinfo($splower)]} {
                    lappend todo $splower
                }
                if {![info exists outputports($splower)]} {
                    set outputports($splower) 1
                }
            }
        }

        set opened 0
        if {[info exists outputports($p)] && $outputports($p) == 1} {
            if {[info exists portinfo(replaced_by)]} {
                puts stderr "Excluding $portinfo(name) because it is replaced by $portinfo(replaced_by)"
                set outputports($p) 0
            } elseif {[info exists portinfo(known_fail)] && [string is true -strict $portinfo(known_fail)]} {
                puts stderr "Excluding $portinfo(name) because it is known to fail"
                set outputports($p) 0
            } elseif {$archive_site_public ne ""} {
                # FIXME: support non-default variants
                if {![catch {mportopen $portinfo(porturl) [list subport $portinfo(name)] ""} result]} {
                    set opened 1
                    set workername [ditem_key $result workername]
                    set archive_name [$workername eval {portfetch::percent_encode [get_portimage_name]}]
                    if {![catch {curl getsize ${archive_site_public}/$portinfo(name)/${archive_name}} size] && $size > 0} {
                        puts stderr "Excluding $portinfo(name) because it has already been built and uploaded to the public server"
                        set outputports($p) 0
                    }
                } else {
                    puts stderr "Excluding $portinfo(name) because it failed to open: $result"
                    set outputports($p) 0
                }
                if {$outputports($p) == 1 && $archive_site_private ne "" && $jobs_dir ne ""} {
                    # FIXME: support non-default variants
                    set results [check_licenses $portinfo(name) [list]]
                    if {[lindex $results 0] == 1 && ![catch {curl getsize ${archive_site_private}/$portinfo(name)/${archive_name}} size] && $size > 0} {
                        puts stderr "Excluding $portinfo(name) because it is not distributable and it has already been built and uploaded to the private server"
                        set outputports($p) 0
                    }
                }
            }
            if {$outputports($p) == 1 && $::macports::os_major <= 10} {
                if {$opened == 1 || ![catch {mportopen $portinfo(porturl) [list subport $portinfo(name)] ""} result]} {
                    set supported_archs [_mportkey $result supported_archs]
                    if {$::macports::os_arch eq "i386" && !${is_64bit_capable} && $supported_archs ne "" && ("x86_64" ni $supported_archs || "i386" ni $supported_archs)} {
                        puts stderr "Excluding $portinfo(name) because the ${::macports::macosx_version}_x86_64 builder will build it"
                        set outputports($p) 0
                    } elseif {$::macports::os_arch eq "powerpc" && $supported_archs ne "" && $supported_archs ne "noarch" && "ppc" ni $supported_archs} {
                        puts stderr "Excluding $portinfo(name) because it does not support the ppc arch"
                        set outputports($p) 0
                    }
                } else {
                    puts stderr "Excluding $portinfo(name) because it failed to open: $result"
                    set outputports($p) 0
                }
            }
            if {$outputports($p) == 1} {
                set canonicalnames($p) $portinfo(name)
            }
        }

        if {![info exists outputports($p)] || $outputports($p) == 1} {
            set deplist [list]
            foreach depstype $depstypes {
                if {[info exists portinfo($depstype)] && $portinfo($depstype) ne ""} {
                    foreach onedep $portinfo($depstype) {
                        set depname [string tolower [lindex [split [lindex $onedep 0] :] end]]
                        lappend deplist $depname
                        lappend todo $depname
                    }
                }
            }
            set portdepinfo($p) $deplist
        }

        array unset portinfo
    }
}

if {$jobs_dir ne "" && $license_db_dir ne "" && $archive_site_public ne "" && $archive_site_private ne ""} {
    write_license_db $license_db_dir
}

set portlist [list]
foreach portname [lsort -dictionary [array names portdepinfo]] {
   if {[info exists portdepinfo($portname)]} {
      process_port_deps $portname portdepinfo portlist
   }
}

foreach portname $portlist {
    if {[info exists outputports($portname)] && $outputports($portname) == 1} {
        puts $canonicalnames($portname)
    }
}
