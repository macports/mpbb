#!/usr/bin/env port-tclsh
#
# Generates a list of ports where a port is only listed after all of its
# dependencies (sans variants) have already been listed. Includes all
# sub-ports of the specified ports.
#
# Copyright (c) 2006,2008 Bryan L Blackburn.  All rights reserved.
# Copyright (c) 2018-2019 The MacPorts Project
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
# 3. Neither the name Bryan L Blackburn, nor the names of any contributors
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
#

package require macports
package require fetch_common


proc ui_prefix {priority} {
   return "OUT: "
}


proc ui_channels {priority} {
   return {}
}


proc process_port_deps {portname} {
    set deplist [dict get $::portdepinfo $portname]
    dict unset ::portdepinfo $portname
    if {[dict exists $::portsoftdeps $portname]} {
        lappend deplist {*}[dict get $::portsoftdeps $portname]
        dict unset ::portsoftdeps $portname
    }
    foreach portdep $deplist {
        if {[dict exists $::portdepinfo $portdep]} {
            process_port_deps $portdep
        }
    }
    lappend ::portlist $portname
}

proc check_failing_deps {portname} {
    if {[dict exists $::failingports $portname]} {
        return [dict get $::failingports $portname]
    }
    # Protect against dependency cycles
    dict set ::failingports $portname [list 3 $portname]
    foreach portdep [dict get $::portdepinfo $portname] {
        set dep_ret [check_failing_deps $portdep]
        # 0 = ok, 1 = known_fail, 2 = failcache, 3 = dep cycle
        set status [lindex $dep_ret 0]
        if {$status != 0} {
            set failed_dep [lindex $dep_ret 1]
            if {[dict get $::outputports $portname] == 1} {
                if {$status == 1} {
                    if {[dict exists $::requestedports $portname]} {
                        puts stderr "Excluding [dict get $::canonicalnames $portname] because its dependency '$failed_dep' is known to fail"
                    }
                    dict set ::outputports $portname 0
                } elseif {$status == 2 && ![dict exists $::requestedports $portname]} {
                    # Exclude deps that will fail due to their own dep being in the failcache.
                    # But still output requested ports so the failure will be reported.
                    dict set ::outputports $portname 0
                } elseif {$status == 3} {
                    if {[dict exists $::requestedports $portname]} {
                        puts stderr "Warning: [dict get $::canonicalnames $portname] appears to have a cyclic dependency involving '$portdep'"
                    }
                    # Some cycles involving depends_test exist, which don't cause
                    # problems yet only because we don't run tests.
                    #dict set ::outputports $portname 0
                }
            }
            # keep processing other deps for now if there was a dep cycle
            if {$status != 3} {
                dict set ::failingports $portname [list $status $failed_dep]
                return [dict get $::failingports $portname]
            }
        }
    }
    dict set ::failingports $portname [list 0 ""]
    return [dict get $::failingports $portname]
}

source [file join [file dirname [info script]] failcache.tcl]

if {[catch {mportinit "" "" ""} result]} {
   puts stderr "$errorInfo"
   error "Failed to initialize ports system: $result"
}

set archive_site_private ""
set archive_site_public ""
set failcache_dir ""
set jobs_dir ""
set license_db_dir ""
set include_deps no
while {[string range [lindex $::argv 0] 0 1] eq "--"} {
    switch -- [lindex $::argv 0] {
        --archive_site_private {
            set archive_site_private [lindex $::argv 1]
            set ::argv [lrange $::argv 1 end]
        }
        --archive_site_public {
            set archive_site_public [lindex $::argv 1]
            set ::argv [lrange $::argv 1 end]
        }
        --failcache_dir {
            set failcache_dir [lindex $::argv 1]
            set ::argv [lrange $::argv 1 end]
        }
        --jobs_dir {
            set jobs_dir [lindex $::argv 1]
            set ::argv [lrange $::argv 1 end]
        }
        --license_db_dir {
            set license_db_dir [lindex $::argv 1]
            set ::argv [lrange $::argv 1 end]
        }
        --include_deps {
            set include_deps yes
        }
        default {
            error "unknown option: [lindex $::argv 0]"
        }
    }
    set ::argv [lrange $::argv 1 end]
}

if {$jobs_dir ne "" && $archive_site_public ne "" && $archive_site_private ne ""} {
    source ${jobs_dir}/distributable_lib.tcl
    if {$license_db_dir ne ""} {
        init_license_db $license_db_dir
    }
}

set is_64bit_capable [sysctl hw.cpu64bit_capable]

set portdepinfo [dict create]
set portsoftdeps [dict create]
set canonicalnames [dict create]
set failingports [dict create]
set todo [list]
if {[lindex $argv 0] eq "-"} {
    while {[gets stdin line] >= 0} {
        lappend todo [string tolower [string trim $line]]
    }
} else {
    foreach p $argv {
        lappend todo [string tolower $p]
    }
}
# save the ones that the user actually wants to know about
set inputports [dict create]
set outputports [dict create]
set requestedports [dict create]
foreach p $todo {
    dict set inputports $p 1
    dict set outputports $p 1
    dict set requestedports $p 1
}
# process all recursive deps
set depstypes [list depends_fetch depends_extract depends_patch depends_build depends_lib depends_run]
while {[llength $todo] > 0} {
    set p [lindex $todo 0]
    set todo [lreplace ${todo}[set todo {}] 0 0]

    if {![dict exists $portdepinfo $p]} {
        if {[catch {mportlookup $p} result]} {
            puts stderr "$errorInfo"
            error "Failed to find port '$p': $result"
        }
        if {[llength $result] < 2} {
            puts stderr "port $p not found in the index"
            dict set portdepinfo $p ""
            dict set outputports $p 0
            continue
        }

        set portinfo [lindex $result 1]

        if {[dict exists $inputports $p]} {
            if {$failcache_dir ne ""} {
                failcache_clear_all [dict get $portinfo name]
            }
            if {[dict exists $portinfo subports]} {
                foreach subport [dict get $portinfo subports] {
                    set splower [string tolower $subport]
                    if {![dict exists $portdepinfo $splower]} {
                        lappend todo $splower
                    }
                    if {![dict exists $requestedports $splower]} {
                        dict set outputports $splower 1
                        dict set requestedports $splower 1
                    }
                }
            }
        }

        set opened 0
        if {[dict get $outputports $p] == 1} {
            if {[dict exists $portinfo replaced_by]} {
                if {[dict exists $requestedports $p]} {
                    puts stderr "Excluding [dict get $portinfo name] because it is replaced by [dict get $portinfo replaced_by]"
                }
                dict set outputports $p 0
            } elseif {[dict exists $portinfo known_fail] && [string is true -strict [dict get $portinfo known_fail]]} {
                if {[dict exists $requestedports $p]} {
                    puts stderr "Excluding [dict get $portinfo name] because it is known to fail"
                }
                dict set outputports $p 0
                dict set failingports $p [list 1 [dict get $portinfo name]]
            } elseif {$failcache_dir ne "" && ![dict exists $requestedports $p]} {
                # exclude dependencies with a failcache entry
                if {![catch {mportopen [dict get $portinfo porturl] [dict create subport [dict get $portinfo name]] ""} result]} {
                    set opened 1
                    set mport $result
                    set portinfo [dict merge $portinfo [mportinfo $mport]]
                    if {![dict exists $portinfo canonical_active_variants]} {
                        puts stderr "Warning: [dict get $portinfo name] has no canonical_active_variants"
                        dict set outputports $p 0
                    } elseif {[check_failcache [dict get $portinfo name] [dict get $portinfo porturl] [dict get $portinfo canonical_active_variants]] != 0} {
                        dict set outputports $p 0
                        dict set failingports $p [list 2 [dict get $portinfo name]]
                    }
                } else {
                    dict set outputports $p 0
                }
            }
            if {$archive_site_public ne "" && [dict get $outputports $p] == 1} {
                # FIXME: support non-default variants
                if {$opened == 1 || ![catch {mportopen [dict get $portinfo porturl] [dict create subport [dict get $portinfo name]] ""} result]} {
                    if {$opened != 1} {
                        set opened 1
                        set mport $result
                        set portinfo [dict merge $portinfo [mportinfo $mport]]
                    }
                    set workername [ditem_key $mport workername]
                    set archive_name [$workername eval {get_portimage_name}]
                    set archive_name_encoded [portfetch::percent_encode $archive_name]
                    if {![catch {curl getsize ${archive_site_public}/[dict get $portinfo name]/${archive_name_encoded}} size] && $size > 0} {
                        # Check for other installed variants that might not have been uploaded
                        set archives_prefix ${macports::portdbpath}/software/[dict get $portinfo name]/[dict get $portinfo name]-[dict get $portinfo version]_[dict get $portinfo revision]
                        set any_archive_missing 0
                        foreach installed_archive [glob -nocomplain -tails -path ${archives_prefix} *] {
                            if {$installed_archive ne $archive_name} {
                                set installed_archive_encoded [portfetch::percent_encode $installed_archive]
                                if {[catch {curl getsize ${archive_site_public}/[dict get $portinfo name]/${installed_archive_encoded}} size] || $size <= 0} {
                                    set any_archive_missing 1
                                    puts stderr "$installed_archive installed but not uploaded"
                                    break
                                }
                            }
                        }
                        if {!$any_archive_missing} {
                            if {[dict exists $requestedports $p]} {
                                puts stderr "Excluding [dict get $portinfo name] because it has already been built and uploaded to the public server"
                            }
                            dict set outputports $p 0
                        }
                    }
                } else {
                    if {[dict exists $requestedports $p]} {
                        puts stderr "Excluding [dict get $portinfo name] because it failed to open: $result"
                    }
                    dict set outputports $p 0
                }
                if {[dict get $outputports $p] == 1 && $archive_site_private ne "" && $jobs_dir ne ""} {
                    # FIXME: support non-default variants
                    set results [check_licenses [dict get $portinfo name] [list]]
                    if {[lindex $results 0] == 1 && ![catch {curl getsize ${archive_site_private}/[dict get $portinfo name]/${archive_name_encoded}} size] && $size > 0} {
                        if {[dict exists $requestedports $p]} {
                            puts stderr "Excluding [dict get $portinfo name] because it is not distributable and it has already been built and uploaded to the private server"
                        }
                        dict set outputports $p 0
                    }
                }
            }
            if {[dict get $outputports $p] == 1 &&
                ($::macports::os_major <= 10 || $::macports::os_major >= 18)} {
                if {$opened == 1 || ![catch {mportopen [dict get $portinfo porturl] [dict create subport [dict get $portinfo name]] ""} result]} {
                    if {$opened != 1} {
                        set opened 1
                        set mport $result
                        set portinfo [dict merge $portinfo [mportinfo $mport]]
                    }
                    set supported_archs [_mportkey $mport supported_archs]
                    switch $::macports::os_arch {
                        arm {
                            if {$supported_archs ne "" && $supported_archs ne "noarch" && "arm64" ni $supported_archs} {
                                if {[dict exists $requestedports $p]} {
                                    puts stderr "Excluding [dict get $portinfo name] because it does not support the arm64 arch"
                                }
                                dict set outputports $p 0
                            }
                        }
                        i386 {
                            if {${is_64bit_capable}} {
                                if {$::macports::os_major >= 18 && $supported_archs ne "" && $supported_archs ne "noarch" && "x86_64" ni $supported_archs} {
                                    if {[dict exists $requestedports $p]} {
                                        puts stderr "Excluding [dict get $portinfo name] because it does not support the x86_64 arch"
                                    }
                                    dict set outputports $p 0
                                }
                            } elseif {$supported_archs ne "" && $supported_archs ne "noarch" && ("x86_64" ni $supported_archs || "i386" ni $supported_archs)} {
                                if {[dict exists $requestedports $p]} {
                                    puts stderr "Excluding [dict get $portinfo name] because the ${::macports::macosx_version}_x86_64 builder will build it"
                                }
                                dict set outputports $p 0
                            }
                        }
                        powerpc {
                            if {$supported_archs ne "" && $supported_archs ne "noarch" && "ppc" ni $supported_archs} {
                                if {[dict exists $requestedports $p]} {
                                    puts stderr "Excluding [dict get $portinfo name] because it does not support the ppc arch"
                                }
                                dict set outputports $p 0
                            }
                        }
                        default {}
                    }
                } else {
                    puts stderr "Excluding [dict get $portinfo name] because it failed to open: $result"
                    dict set outputports $p 0
                }
            }
        }

        if {$opened} {
            mportclose $mport
        }

        if {[dict get $outputports $p] == 1} {
            dict set canonicalnames $p [dict get $portinfo name]
        }

        # If $requestedports($p) == 0, we're seeing the port again as a dependency of
        # something else and thus need to follow its deps even if it was excluded.
        if {[dict get $outputports $p] == 1 || ![dict exists $requestedports $p] || [dict get $requestedports $p] == 0} {
            dict set portdepinfo $p [list]
            foreach depstype $depstypes {
                if {[dict exists $portinfo $depstype] && [dict get $portinfo $depstype] ne ""} {
                    foreach onedep [dict get $portinfo $depstype] {
                        set depname [string tolower [lindex [split [lindex $onedep 0] :] end]]
                        if {[string match port:* $onedep]} {
                            dict lappend portdepinfo $p $depname
                        } else {
                            # soft deps are installed before their dependents, but
                            # don't cause exclusion if they are failing
                            # real problematic example: bin:xattr:xattr
                            dict lappend portsoftdeps $p $depname
                        }
                        if {![dict exists $outputports $depname]} {
                            lappend todo $depname
                            if {$include_deps} {
                                dict set outputports $depname 1
                            } else {
                                dict set outputports $depname 0
                            }
                        } elseif {[dict exists $requestedports $depname] && ![dict exists $portdepinfo $depname]} {
                            # may or may not have been checked for exclusion yet
                            lappend todo $depname
                        }
                    }
                }
            }
        }

        # Mark as having been processed at least once.
        if {[dict exists $requestedports $p]} {
            dict set requestedports $p 0
        }
    }
}

if {$jobs_dir ne "" && $license_db_dir ne "" && $archive_site_public ne "" && $archive_site_private ne ""} {
    write_license_db $license_db_dir
}

set sorted_portnames [lsort -dictionary [dict keys $portdepinfo]]
foreach portname $sorted_portnames {
    check_failing_deps $portname
}

set portlist [list]
foreach portname $sorted_portnames {
   if {[dict exists $portdepinfo $portname]} {
      process_port_deps $portname
   }
}

foreach portname $portlist {
    if {[dict get $outputports $portname] == 1} {
        puts [dict get $canonicalnames $portname]
    }
}
