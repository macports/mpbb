#!/usr/bin/env tclsh
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

catch {source \
   [file join "/" Library Tcl macports1.0 macports_fastload.tcl]}
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
   puts "$errorInfo"
   fatal "Failed to initialize ports sytem: $result"
}

if {[catch {set search_result [mportsearch ^.+$ no]} result]} {
   puts "$errorInfo"
   fatal "Failed to find any ports: $result"
}

array set portdepinfo {}
foreach {name infoarray} $search_result {
   array set portinfo $infoarray
   set depstypes {depends_build depends_lib depends_run}
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

set portlist [list]
foreach portname [lsort -dictionary [array names portdepinfo]] {
   process_port_deps $portname portdepinfo portlist
}

puts [join $portlist "\n"]

