#!/usr/bin/env port-tclsh
# -*- coding: utf-8; mode: tcl; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- vim:fenc=utf-8:ft=tcl:et:sw=4:ts=4:sts=4
# Writes a list of dependencies for a given port including variants (e.g. if
# the universal variant is required) to stdout.
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

package require macports

if {[llength $::argv] == 0} {
    puts stderr "Usage: $argv0 <portname>"
    exit 1
}

# initialize macports
if {[catch {mportinit "" "" ""} result]} {
   ui_error "$errorInfo"
   ui_error "Failed to initialize ports sytem: $result"
   exit 1
}

# look up the path of the Portfile for the given port
set portname [lindex $::argv 0]
#try -pass_signal {
try {
    set result [mportlookup $portname]
    if {[llength $result] < 2} {
        ui_error "No such port: $portname"
        exit 1
    }
} catch {{*} eCode eMessage} {
    ui_error "mportlookup $portname failed: $eMessage"
    exit 1
}

# open the port so we can run dependency calculation
array set portinfo [lindex $result 1]
#try -pass_signal {
try {
    set mport [mportopen $portinfo(porturl) [list subport $portname] {}]
} catch {{*} eCode eMessage} {
    ui_error "mportopen ${portinfo(porturl)} failed: $eMessage"
    exit 1
}

# gather a list of dependencies with the correct variants (+universal is dealt
# with in specific ways)
if {[mportdepends $mport "activate"] != 0} {
    ui_error "mportdepends $portname activate failed."
    exit 1
}

# sort these dependencies topologically; exclude the given port itself
set dlist [dlist_append_dependents $macports::open_mports $mport {}]
dlist_delete dlist $mport

## print dependencies with variants
foreach ditem $dlist {
    set depname [ditem_key $ditem provides]
    array set depinfo [mportinfo $ditem]

    puts [string trim "$depname $depinfo(canonical_active_variants)"]
}

# close all open ports
foreach ditem $dlist {
    #try -pass_signal {
    try {
        mportclose $ditem
    } catch {{*} eCode eMessage} {
        ui_warn "mportclose [ditem_key $ditem provides] failed: $eMessage"
    }
}
#try -pass_signal {
try {
    mportclose $mport
} catch {{*} eCode eMessage} {
    ui_error "mportclose $portname failed: $eMessage"
    exit 1
}

# shut down MacPorts
#try -pass_signal {
try {
    mportshutdown
} catch {{*} eCode eMessage} {
    ui_error "mportshutdown failed: $eMessage"
    exit 1
}
