#!/usr/bin/env port-tclsh
#
# clear out stale entries and entries for deleted ports from the failcache

package require macports
mportinit

source [file join [file dirname [info script]] failcache.tcl]

set failcache_dir ""
while {[string range [lindex $::argv 0] 0 1] eq "--"} {
    switch -- [lindex $::argv 0] {
        --failcache_dir {
            set failcache_dir [lindex $::argv 1]
            set ::argv [lrange $::argv 1 end]
        }
        default {
            error "unknown option: [lindex $::argv 0]"
        }
    }
    set ::argv [lrange $::argv 1 end]
}

if {$failcache_dir eq ""} {
    error "must specify --failcache_dir"
}

 foreach f [glob -directory $failcache_dir -nocomplain -tails *] {
    lassign [split $f " "] entry_portname entry_variants entry_hash
    set result [mportlookup $entry_portname]
    if {[llength $result] < 2} {
        puts "Port '$entry_portname' no longer exists; removing failcache entry $f"
        file delete -force [file join $failcache_dir $f]
        continue
    }
    array unset portinfo
    array set portinfo [lindex $result 1]
    set hash [port_files_checksum $portinfo(porturl)]
    if {$entry_hash ne $hash} {
        puts "Removing stale failcache entry: $f"
        file delete -force [file join $failcache_dir $f]
    }
 }
 
