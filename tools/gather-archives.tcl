#!/usr/bin/env port-tclsh

package require macports
package require registry2
package require fetch_common

set archive_site_private https://packages-private.macports.org
set archive_site_public https://packages.macports.org
set jobs_dir ""
set license_db_dir ""
set staging_dir ""
while {[string range [lindex $::argv 0] 0 1] eq "--"} {
    switch -- [lindex $::argv 0] {
        --archive_site_private {
            set archive_site_private [lindex $::argv 1]
            set ::argv [lreplace $::argv 0 0]
        }
        --archive_site_public {
            set archive_site_public [lindex $::argv 1]
            set ::argv [lreplace $::argv 0 0]
        }
        --jobs_dir {
            set jobs_dir [file normalize [lindex $::argv 1]]
            set ::argv [lreplace $::argv 0 0]
        }
        --license_db_dir {
            set license_db_dir [file normalize [lindex $::argv 1]]
            set ::argv [lreplace $::argv 0 0]
        }
        --staging_dir {
            set staging_dir [file normalize [lindex $::argv 1]]
            set ::argv [lreplace $::argv 0 0]
        }
        default {
            error "unknown option: [lindex $::argv 0]"
        }
    }
    set ::argv [lreplace $::argv 0 0]
}

if {$staging_dir eq ""} {
    error "must specify --staging_dir"
}
if {$jobs_dir eq ""} {
    error "must specify --jobs_dir"
}
if {[llength $::argv] == 0} {
    error "must specify an input file"
}

if {[catch {mportinit "" "" ""} result]} {
   puts stderr "$errorInfo"
   error "Failed to initialize ports system: $result"
}

source ${jobs_dir}/distributable_lib.tcl
if {$license_db_dir ne ""} {
    init_license_db $license_db_dir
}

set tarcmd "$macports::autoconf::tar_path [macports::get_tar_flags .${macports::portarchivetype}]cvf"

file stat $staging_dir stat_array
set staging_device $stat_array(dev)

set infd [open [lindex $::argv 0] r]
while {[gets $infd line] >= 0} {
    set portname [lindex [split $line] 0]
    if {[catch {mportlookup $portname} result]} {
        puts stderr "$errorInfo"
        puts stderr "Failed to look up port '$portname': $result"
        continue
    } elseif {[llength $result] < 2} {
        puts stderr "port $portname not found in the index"
        continue
    }

    lassign $result portname portinfo

    foreach e [registry::entry imaged $portname] {
        if {[$e version] ne [dict get $portinfo version] || [$e revision] != [dict get $portinfo revision]} {
            puts "Skipping [$e name] @[$e version]_[$e revision][$e variants] (not current)"
            continue
        }
        set requested_variations [split_variants [$e requested_variants]]
        
        lassign [check_licenses [$e name] $requested_variations] license_result license_reason
        puts $license_reason
        if {$license_result == 0} {
            set archive_type public
            set archive_site $archive_site_public
        } else {
            set archive_type private
            set archive_site $archive_site_private
        }
        set portimage_path [$e location]
        # Port image may sometimes be a directory
        if {[file isfile $portimage_path]} {
            set archive_path $portimage_path
            set staging_operation copy
        } else {
            set archive_path ${portimage_path}.${macports::portarchivetype}
            # Check if an archive also exists
            if {[file isfile $archive_path]} {
                # The archive is not the image, so it can be safely
                # deleted after staging.
                set staging_operation move
            } elseif {[file isdirectory $portimage_path]} {
                # The archive was either somehow never created, or
                # has since been deleted. Recreate it if needed.
                set staging_operation create
            } else {
                # No portimage at all
                puts "Image for [$e name] @[$e version]_[$e revision][$e variants] seems to be missing"
                continue
            }
        }
        set archive_basename [file tail $archive_path]
        set archive_name_encoded [portfetch::percent_encode $archive_basename]
        if {![catch {curl getsize ${archive_site}/[$e name]/${archive_name_encoded}} size] && $size > 0} {
            puts "Already uploaded ${archive_type} archive: ${archive_basename}"
            continue
        }

        puts "Staging ${archive_type} archive for upload: ${archive_basename}"
        set archive_staging_dir [file join ${staging_dir} ${archive_type} [$e name]]
        file mkdir $archive_staging_dir
        switch $staging_operation {
            copy {
                file stat $archive_path stat_array
                if {$stat_array(dev) == $staging_device} {
                    puts "creating hardlink to $archive_path in $archive_staging_dir"
                    file link -hard [file join $archive_staging_dir $archive_basename] $archive_path
                } else {
                    puts "copying $archive_path to $archive_staging_dir"
                    file copy -force -- $archive_path $archive_staging_dir
                }
            }
            create {
                puts "creating $archive_basename from $portimage_path"
                system -W $portimage_path "$tarcmd [file join $archive_staging_dir $archive_basename] ."
            }
            move {
                puts "moving $archive_path to $archive_staging_dir"
                file rename -force -- $archive_path $archive_staging_dir
            }
        }
    }
}

if {$license_db_dir ne ""} {
    write_license_db $license_db_dir
}

exit 0
