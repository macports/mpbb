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

        mpbb selfupdate --prefix /opt/local

2.  Checkout ports tree and update the portindex.

        mpbb checkout \
            --prefix /opt/local \
            --work-dir /tmp/scratch \
            --svn-url https://svn.macports.org/repository/macports/trunk \
            --svn-revision 123456

3.  Print to standard output a list of all subports for one port...

        mpbb list-subports --prefix /opt/local --port php

    ...or for several.

        mpbb list-subports --prefix /opt/local cmake llvm-3.8 ...

4.  For each subport listed in step 3:

    a.  Install dependencies.

            mpbb install-dependencies \
                --prefix /opt/local \
                --port php71

    b.  Install the subport itself.

            mpbb install-port --prefix /opt/local --port php71

    c.  Gather archives.

            mpbb gather-archives \
                --prefix /opt/local \
                --work-dir /tmp/scratch \
                --archive-site https://packages.macports.org \
                --staging-dir /tmp/scratch/staging

    d.  Upload. Must be implemented in the buildmaster.

    e.  Deploy. Must be implemented in the buildmaster.

    f.  Clean up. This must always be run, even if a previous step
        failed.

            mpbb cleanup --prefix /opt/local


## Subcommand API ##

Subcommand scripts are sourced by the `mpbb` driver. A script named
`mpbb-SUBCOMMAND` must define these two shell functions:

-   `SUBCOMMAND()`:
      Perform the subcommand's work when invoked by the driver.
-   `SUBCOMMAND-help()`:
      Print a brief summary of the subcommand's purpose to standard
      output, but do not `exit`. The driver converts newlines to spaces
      in the final output.

Scripts may define additional functions as desired. For example, the
`mpbb-list-subports` script defines the required `list-subports` and
`list-subports-help` functions, as well as a `print-subports` helper.

Subcommand scripts may use but not modify these global shell parameters:

-   `$command`:
      The name of the subcommand.
-   `$option_archive_site`:
      The URL of the mirror to check for preexisting archives.
-   `$option_port`:
      The name of the port to install.
-   `$option_prefix`:
      The prefix of the MacPorts installation.
-   `$option_staging_dir`:
      The directory for staging distributable archives for upload.
-   `$option_svn`:
      The path to the Subversion executable.
-   `$option_svn_revision`:
      The revision to checkout from the `$option_svn_url` repository.
-   `$option_svn_url`:
      The URL of a Subversion repository containing the MacPorts `base`
      and `dports` directory trees.
-   `$option_work_dir`:
      A directory for storing temporary data. It is guaranteed to
      persist for the duration of an `mpbb` run, so it may be used to
      share ancillary files (e.g., a Subversion checkout of the ports
      tree) between builds of different ports.
