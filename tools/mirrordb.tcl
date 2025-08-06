# common code for mirror database

set portfile_hash_cache [dict create]
set portname_portfile_map [dict create]

proc get_portfile_hash {portname} {
    global portfile_hash_cache portname_portfile_map
    if {[dict exists $portname_portfile_map $portname]} {
        set portfile [dict get $portname_portfile_map $portname]
    } else {
        set result [mportlookup $portname]
        if {[llength $result] < 2} {
            return {}
        }
        set portinfo [lindex $result 1]
        set portfile [file join [macports::getportdir [dict get $portinfo porturl]] Portfile]
        dict set portname_portfile_map $portname $portfile
    }
    if {[dict exists $portfile_hash_cache $portfile]} {
        return [dict get $portfile_hash_cache $portfile]
    } elseif {[file isfile $portfile]} {
        set portfile_hash [sha256 file $portfile]
        dict set portfile_hash_cache $portfile $portfile_hash
        return $portfile_hash
    }
    return {}
}

proc get_remote_db_value {key} {
     global mirrorcache_baseurl mirrorcache_credentials
     set fullurl ${mirrorcache_baseurl}GET/${key}?type=txt
     try {
        curl fetch -u $mirrorcache_credentials $fullurl mirror_db_response
        set fd [open mirror_db_response r]
        gets $fd result
        close $fd
    } on error {err} {
        if {$err ne "The requested URL returned error: 404"} {
            puts stderr "get_remote_db_value: curl failed for key '$key': $err"
        }
        set result {}
    } finally {
        file delete mirror_db_response
    }
    return $result
}
