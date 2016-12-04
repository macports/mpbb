#!/usr/bin/env port-tclsh
#
# Prints the archive filename for the given port with the given variants.
#
# Copyright © 2013, 2016 The MacPorts Project.
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

proc split_variants {variants} {
    set result {}
    set l [regexp -all -inline -- {([-+])([[:alpha:]_]+[\w\.]*)} $variants]
    foreach { match sign variant } $l {
        lappend result $variant $sign
    }
    return $result
}

package require macports

if {[catch {mportinit "" "" ""} result]} {
   ui_error "$errorInfo"
   ui_error "Failed to initialize ports system: $result"
   exit 1
}

set portname [lindex $::argv 0]
if {[llength $::argv] > 1} {
    set variations [split_variants [lindex $::argv 1]]
} else {
    set variations ""
}

if {[catch {set one_result [mportlookup $portname]}] || [llength $one_result] < 2} {
    # just print whatever, mpbb will notice the missing port itself
    puts "nonexistent"
    exit 0
}

array set portinfo [lindex $one_result 1]
if {[info exists portinfo(porturl)]} {
    if {[catch {set mport [mportopen $portinfo(porturl) [list subport $portinfo(name)] $variations]}]} {
        ui_warn "failed to open port: $portname"
        puts "nonexistent"
        exit 0
    } else {
        set workername [ditem_key $mport workername]
        puts [$workername eval get_portimage_path]
    }
}
