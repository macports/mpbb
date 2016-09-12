# MacPorts Buildbot Scripts #

This is a collection of scripts that will be run by the MacPorts
Project's Buildbot buildslaves for continuous integration and
precompilation of binary archives.


## General Structure ##

The `mpbb` ("MacPorts Buildbot") driver script defines a subcommand for
each step of a build. These subcommands are implemented as separate
scripts named `mpbb-SUBCOMMAND`, but they are not intended to be
standalone programs and should not be executed as such. Build steps
should only be run using the `mpbb` driver.

The defined build steps are:

1.  Update base without updating the portindex.

        mpbb --prefix /opt/local selfupdate

2.  Checkout ports tree and update the portindex.

        mpbb --prefix /opt/local --work-dir /tmp/scratch \
            checkout \
            --svn-url https://svn.macports.org/repository/macports/trunk \
            --svn-revision 123456

3.  Print one or more ports' subports to standard output.

        mpbb --prefix /opt/local list-subports php cmake llvm-3.8 [...]

4.  For each subport listed in step 3:

    a.  Install dependencies.

            mpbb --prefix /opt/local install-dependencies php71

    b.  Install the subport itself.

            mpbb --prefix /opt/local install-port php71

    c.  Gather archives.

            mpbb --prefix /opt/local --work-dir /tmp/scratch \
                gather-archives \
                --archive-site https://packages.macports.org \
                --staging-dir /tmp/scratch/staging

    d.  Upload. Must be implemented in the buildmaster.

    e.  Deploy. Must be implemented in the buildmaster.

    f.  Clean up. This must always be run, even if a previous step
        failed.

            mpbb --prefix /opt/local cleanup


## Subcommand API ##

Subcommand scripts are sourced by the `mpbb` driver. A script named
`mpbb-SUBCOMMAND` must define these two shell functions:

-   `SUBCOMMAND()`:
      Perform the subcommand's work and return zero on success and
      nonzero on failure.
-   `SUBCOMMAND-usage()`:
      Print to standard out a usage summary, a description of the
      subcommand's purpose, and the subcommand's options, but do not
      `exit`. The output is passed through `fmt(1)`, so single newlines
      are not preserved.

Scripts may define additional functions as desired. For example, the
`mpbb-list-subports` script defines the required `list-subports` and
`list-subports-usage` functions, as well as a `print-subports` helper.

Subcommand scripts may use but not modify these global shell parameters:

-   `$command`:
      The name of the subcommand.
-   `$option_prefix`:
      The prefix of the MacPorts installation.
-   `$option_jobs_dir`:
      The path to a local copy of the
      [jobs tools](https://trac.macports.org/browser/trunk/base/portmgr/jobs).
-   `$option_log_dir`:
      A directory for storing build logs.
-   `$option_work_dir`:
      A directory for storing temporary data. It is guaranteed to
      persist for the duration of an `mpbb` run, so it may be used to
      share ancillary files (e.g., a Subversion checkout of the ports
      tree) between builds of different ports.
-   `$option_failcache_dir`:
      A directory for storing information about previously failed builds which
      saves time because builds that are known to fail will not be attempted.


## Runtime Requirements ##

-   `mpbb` is written in [bash](https://www.gnu.org/software/bash) and
    is known to be compatible with 3.2.17 through 3.2.57.
-   Library functions
    -   `compute_failcache_hash` requires an
        [OpenSSL](https://www.openssl.org) that can generate SHA256 digests.
    -   `parseopt` requires [Frodo Looijaard's enhanced
        `getopt(1)`](http://frodo.looijaard.name/project/getopt),
        which is available from the `getopt` port.
-   Subcommands
    -   Any subcommand involving ports requires MacPorts, obviously.
    -   `mpbb checkout` requires one or both of the
        [Git](https://git-scm.com) and
        [Subversion](http://subversion.apache.org) clients.
    -   `mpbb help` requires
        [`fmt(1)`](https://en.wikipedia.org/wiki/Fmt).
    -   `mpbb gather-archives` requires [curl](https://curl.haxx.se).
    -   `mpbb selfupdate` requires Make.
