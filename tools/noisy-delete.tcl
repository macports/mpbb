#! /usr/bin/env port-tclsh

# Delete files while producing output often enough that buildbot won't
# cancel the build due to timeout.

package require Thread

set noisemaker {
    while {1} {
        # Every 5 minutes
        after 300000
        puts "Still deleting..."
    }
}

thread::create $noisemaker

foreach f $::argv {
    if {[file type $f] eq "link"} {
        file delete -force [file link $f]
    }
    file delete -force $f
}
