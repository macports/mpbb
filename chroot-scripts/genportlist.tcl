#!/bin/sh
# \
if /usr/bin/which -s port-tclsh; then exec port-tclsh "$0" -i `which port-tclsh` "$@"; else exec /usr/bin/tclsh "$0" -i /usr/bin/tclsh "$@"; fi
#
# Generates a list of ports where a port is only listed after all of its
# dependencies (sans variants) have already been listed
#
# Copyright (c) 2006,2008 Bryan L Blackburn.  All rights reserved.
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

if {[info exists env(PREFIX)]} {
    set prefix $env(PREFIX)
} else {
    set prefix /opt/local
}

if {[llength $::argv] >= 2 && [lindex $argv 0] eq "-i"} {
    set prefixFromInterp [file dirname [file dirname [lindex $argv 1]]]
    if {$prefixFromInterp ne $prefix} {
        if {[file executable ${prefix}/bin/port-tclsh]} {
            exec ${prefix}/bin/port-tclsh $argv0 {*}[lrange $::argv 2 end] <@stdin >@stdout 2>@stderr
            exit 0
        } else {
            puts stderr "No port-tclsh found in ${prefix}/bin"
            exit 1
        }
    }
    set ::argv [lrange $::argv 2 end]
}

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
   if {[lsearch -exact $portlist $portname] == -1} {
      if {[info exists portdeps($portname)]} {
         foreach portdep $portdeps($portname) {
            if {[lsearch -exact $portlist $portdep] == -1} {
               process_port_deps $portdep portdeps portlist
            }
         }
      }
      lappend portlist $portname
   }
}


if {[catch {mportinit "" "" ""} result]} {
   puts stderr "$errorInfo"
   error "Failed to initialize ports sytem: $result"
}

set depstypes [list depends_fetch depends_extract depends_build depends_lib depends_run]
array set portdepinfo {}

if {[llength $argv] == 0} {
    # do all ports
    if {[catch {set search_result [mportlistall]} result]} {
       puts stderr "$errorInfo"
       error "Failed to find any ports: $result"
    }

    foreach {name infoarray} $search_result {
       array set portinfo $infoarray
       set deplist [list]
       foreach depstype $depstypes {
          if {[info exists portinfo($depstype)] && $portinfo($depstype) != ""} {
             foreach onedep $portinfo($depstype) {
                lappend deplist [lindex [split [lindex $onedep 0] :] end]
             }
          }
       }
       set portdepinfo($portinfo(name)) $deplist
       array unset portinfo
    }
} else {
    # do a specified list of ports
    if {[lindex $argv 0] eq "-"} {
        set todo [list]
        while {[gets stdin line] >= 0} {
            lappend todo [string trim $line]
        }
    } else {
        set todo $argv
    }
    # save the ones that the caller actually wants to know about
    foreach p $todo {
        set inputports($p) 1
    }
    # process all recursive deps
    while {$todo ne {}} {
        set p [lindex $todo 0]
        set todo [lrange $todo 1 end]
        if {[catch {set lookup_result [mportlookup $p]} result]} {
            puts stderr "$errorInfo"
            error "Failed to find port '$p': $result"
        }
        if {[llength $lookup_result] < 2} {
            puts stderr "port $p not found in the index"
            continue
        }

        array set portinfo [lindex $lookup_result 1]
        if {![info exists portdepinfo($portinfo(name))]} {
            set deplist [list]
            foreach depstype $depstypes {
                if {[info exists portinfo($depstype)] && $portinfo($depstype) != ""} {
                    foreach onedep $portinfo($depstype) {
                        set depname [lindex [split [lindex $onedep 0] :] end]
                        lappend deplist $depname
                        lappend todo $depname
                    }
                }
            }
            set portdepinfo($portinfo(name)) $deplist
        }
        array unset portinfo
    }
}

set portlist [list]
foreach portname [lsort -dictionary [array names portdepinfo]] {
   process_port_deps $portname portdepinfo portlist
}

if {[info exists inputports]} {
    foreach portname $portlist {
        if {[info exists inputports($portname)]} {
            puts $portname
        }
    }
} else {
    puts [join $portlist "\n"]
}

