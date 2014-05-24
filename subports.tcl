#!/bin/sh
#
# \
if /usr/bin/which -s port-tclsh; then exec port-tclsh "$0" -i `which port-tclsh` "$@"; else exec /usr/bin/tclsh "$0" -i /usr/bin/tclsh "$@"; fi
# Generates a list of the subports for the given port.
#
# Copyright (c) 2011 The MacPorts Project.
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

if {[info exists env(PREFIX)]} {
    set prefix $env(PREFIX)
} else {
    set prefix /opt/local
}

if {[llength $::argv] == 0} {
    puts stderr "Usage: $argv0 <portname>"
    exit 1
} elseif {[llength $::argv] >= 3 && [lindex $argv 0] eq "-i"} {
    set prefixFromInterp [file dirname [file dirname [lindex $argv 1]]]
    if {$prefixFromInterp eq "/usr" && [file isfile ${prefix}/share/macports/Tcl/macports1.0/macports_fastload.tcl]} {
        source ${prefix}/share/macports/Tcl/macports1.0/macports_fastload.tcl
    } elseif {$prefixFromInterp ne $prefix} {
        if {[file executable ${prefix}/bin/port-tclsh]} {
            exec ${prefix}/bin/port-tclsh $argv0 {*}[lrange $::argv 2 end] <@stdin >@stdout 2>@stderr
        } else {
            exec /usr/bin/tclsh $argv0 {*}[lrange $::argv 2 end] <@stdin >@stdout 2>@stderr
        }
        exit 0
    }
    set ::argv [lrange $::argv 2 end]
}

package require macports

if {[catch {mportinit "" "" ""} result]} {
   ui_error "$errorInfo"
   ui_error "Failed to initialize ports sytem: $result"
   exit 1
}

set portname [lindex $::argv 0]

if {[catch {set one_result [mportlookup $portname]}] || [llength $one_result] < 2} {
    # just pass it through, MPAB will complain about it later
    puts $portname
    exit 0
}
puts [lindex $one_result 0]
array set portinfo [lindex $one_result 1]
if {[info exists portinfo(porturl)]} {
    if {[catch {set mport [mportopen $portinfo(porturl) "" ""]}]} {
        ui_warn "failed to open port: $portname"
    } else {
        array unset portinfo
        array set portinfo [mportinfo $mport]
        if {[info exists portinfo(subports)]} {
            foreach subport $portinfo(subports) {
                puts $subport
            }
        }
    }
    catch {mportclose $mport}
}
