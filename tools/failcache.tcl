# common code for operating on the failcache

package require sha256

# save in case env gets cleared
if {[info exists ::env(BUILDBOT_BUILDURL)]} {
    set failcache_buildurl $::env(BUILDBOT_BUILDURL)
}

# slightly odd method as per mpbb's compute_failcache_hash
proc port_files_checksum {porturl} {
    set portdir [macports::getportdir $porturl]
    lappend hashlist [::sha2::sha256 -hex -file ${portdir}/Portfile]
    if {[file exists ${portdir}/files]} {
        fs-traverse f [list ${portdir}/files] {
            if {[file type $f] eq "file"} {
                lappend hashlist [::sha2::sha256 -hex -file $f]
            }
        }
    }
    foreach hash [lsort $hashlist] {
        append compound_hash "${hash}\n"
    }
    return [::sha2::sha256 -hex $compound_hash]
}

proc check_failcache {portname porturl canonical_variants {return_contents no}} {
    global failcache_dir
    set hash [port_files_checksum $porturl]
    set key "$portname $canonical_variants $hash"
    set ret 0
    foreach f [glob -directory $failcache_dir -nocomplain -tails "${portname} *"] {
        if {$f eq $key} {
            if {$return_contents} {
                set fd [open [file join $failcache_dir $f] r]
                set line [gets $fd]
                close $fd
                return $line
            }
            set ret 1
        } elseif {[lindex [split $f " "] end] ne $hash} {
            puts stderr "removing stale failcache entry: $f"
            file delete -force [file join $failcache_dir $f]
        }
    }
    return $ret
}

proc failcache_update {portname porturl canonical_variants failed} {
    global failcache_dir
    set hash [port_files_checksum $porturl]
    set entry_path [file join $failcache_dir "$portname $canonical_variants $hash"]
    if {$failed} {
        global env failcache_buildurl
        file mkdir $failcache_dir
        set fd [open $entry_path w]
        if {[info exists env(BUILDBOT_BUILDURL)]} {
            puts $fd $env(BUILDBOT_BUILDURL)
        } elseif {[info exists failcache_buildurl]} {
            puts $fd $failcache_buildurl
        } else {
            puts $fd "unknown"
        }
        close $fd
    } else {
        file delete -force $entry_path
    }
}

# clear all entries for portname
proc failcache_clear_all {portname} {
    global failcache_dir
    foreach f [glob -directory $failcache_dir -nocomplain "${portname} *"] {
        puts stderr "clearing failcache entry: [file tail $f]"
        file delete -force $f
    }
}
