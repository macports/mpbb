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

file delete -force {*}$::argv
