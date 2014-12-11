#!/bin/sh
# \
if /usr/bin/which -s port-tclsh; then exec port-tclsh "$0" -i `which port-tclsh` "$@"; else exec /usr/bin/tclsh "$0" -i /usr/bin/tclsh "$@"; fi

proc printUsage {} {
    puts "Usage: $::argv0 \[-hV\] \[-p macports-prefix\]"
    puts "  -h    This help"
    puts "  -p    Use a different MacPorts prefix"
    puts "        (defaults to /opt/local)"
    puts "  -V    show version and MacPorts version being used"
}

set MY_VERSION 0.1
set macportsPrefix /opt/local

set showVersion 0

set origArgv $::argv
while {[string index [lindex $::argv 0] 0] == "-" } {
    switch [string range [lindex $::argv 0] 1 end] {
        h {
            printUsage
            exit 0
        }
        i {
            set interp_path [lindex $::argv 1]
            set ::argv [lrange $::argv 1 end]
        }
        p {
            if {[llength $::argv] < 2} {
                puts "-p needs a path"
                printUsage
                exit 2
            }
            set macportsPrefix [lindex $::argv 1]
            set ::argv [lrange $::argv 1 end]
            set userPrefix 1
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

# check that default prefix exists
if {![info exists userPrefix] && ![file isdirectory $macportsPrefix]} {
    error "prefix '$macportsPrefix' does not exist; maybe you need to use the -p option?"
}

if {[info exists interp_path]} {
    set prefixFromInterp [file dirname [file dirname $interp_path]]
    # make sure we're running in the port-tclsh associated with the correct prefix
    if {$prefixFromInterp ne $macportsPrefix} {
        if {[file executable ${macportsPrefix}/bin/port-tclsh]} {
            exec ${macportsPrefix}/bin/port-tclsh $argv0 {*}[lrange $origArgv 2 end] <@stdin >@stdout 2>@stderr
            exit 0
        } else {
            puts stderr "No port-tclsh found in ${macportsPrefix}/bin"
            exit 1
        }
    }
}

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
