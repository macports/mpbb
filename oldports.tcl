#!/usr/bin/tclsh

proc printUsage {} {
    puts "Usage: $::argv0 \[-hV\] \[-t macports-tcl-path\]"
    puts "  -h    This help"
    puts "  -t    Give a different location for the base MacPorts Tcl"
    puts "        file (defaults to /Library/Tcl)"
    puts "  -V    show version and MacPorts version being used"
}

set MY_VERSION 0.1
set macportsTclPath /Library/Tcl

set showVersion 0

while {[string index [lindex $::argv 0] 0] == "-" } {
    switch [string range [lindex $::argv 0] 1 end] {
        h {
            printUsage
            exit 0
        }
        t {
            if {[llength $::argv] < 2} {
                puts "-t needs a path"
                printUsage
                exit 2
            }
            set macportsTclPath [lindex $::argv 1]
            set ::argv [lrange $::argv 1 end]
        }
        V {
            set showVersion 1
        }
        default {
            puts "Unknown option [lindex $::argv 0]"
            printUsage
            exit 2
        }
    }
    set ::argv [lrange $::argv 1 end]
}

source "${macportsTclPath}/macports1.0/macports_fastload.tcl"
package require macports
mportinit

if {$showVersion} {
    puts "Version $MY_VERSION"
    puts "MacPorts version [macports::version]"
    exit 0
}

set ilist [registry::installed]
foreach i $ilist {
        set old 0
        set iname [lindex $i 0]
        set iversion [lindex $i 1]
        set irevision [lindex $i 2]
        set ivariants [lindex $i 3]
        set res [mportlookup $iname]
        if {[llength $res] < 2} {
            # not found in index, classify as old
            set old 1
        } else {
            array unset portinfo
            array set portinfo [lindex $res 1]
            if {$portinfo(version) != $iversion || $portinfo(revision) != $irevision} {
                set old 1
            }
        }
        if {$old} {
            puts "$iname @${iversion}_${irevision}${ivariants}"
        }
}
