#!/usr/bin/env port-tclsh

# args:
# mirrorcache_baseurl mirrorcache_credentials
# then paths to three files containing tcl dicts:
# mirror_done portfile_hash_cache portname_portfile_map

package require Pextlib

lassign $argv mirrorcache_baseurl mirrorcache_credentials mirror_done_p portfile_hash_cache_p portname_portfile_map_p
foreach var {mirror_done portfile_hash_cache portname_portfile_map} {
    set fd [open [set ${var}_p] r]
    set $var [gets $fd]
    close $fd
}

dict for {portname status} $mirror_done {
    if {![dict exists $portname_portfile_map $portname]} {
        puts stderr "$portname not found in portname_portfile_map"
        continue
    }
    set portfile [dict get $portname_portfile_map $portname]
    set hash [dict get $portfile_hash_cache $portfile]
    set hashurl ${mirrorcache_baseurl}SET/mirror.sha256.${portname}/${hash}
    set statusurl ${mirrorcache_baseurl}SET/mirror.status.${portname}/${status}
    curl fetch -u $mirrorcache_credentials $hashurl /dev/null
    curl fetch -u $mirrorcache_credentials $statusurl /dev/null
}
