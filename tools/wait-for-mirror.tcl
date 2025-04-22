#!/usr/bin/env port-tclsh

# Check a remote database to see if mirroring has been attempted for
# the current version of the given port, and if not, wait and check
# periodically until it has been, or timeout is reached.

if {$argc != 3} {
    error "Usage: wait-for-mirror.tcl mirrorcache_baseurl mirrorcache_credentials portname"
}

lassign $argv mirrorcache_baseurl mirrorcache_credentials portname

package require macports
source [file join [file dirname [info script]] mirrordb.tcl]

set ui_options(ports_verbose) yes
if {[catch {mportinit ui_options "" ""} result]} {
   ui_error "$errorInfo"
   ui_error "Failed to initialize ports system: $result"
   exit 1
}

proc main {portname} {
    set portfile_hash [get_portfile_hash $portname]
    set key mirror.sha256.${portname}
    set start [clock seconds]
    while {[get_remote_db_value $key] ne $portfile_hash} {
        # 1h timeout
        if {[clock seconds] - $start >= 3600} {
            return 1
        }
        # 10s delay between queries
        after 10000
    }
    return 0
}

main $portname
