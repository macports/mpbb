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
            --workdir "$workdir" \
            --svn-url "$svnurl" \
            --svn-revision "$svnrev"

3.  Print to standard output a list of all subports for one port...

        mpbb list-subports --prefix /opt/local --port "$port"

    ...or for several.

        mpbb list-subports --prefix /opt/local "$port1" "$port2" ...

4.  For each subport listed in step 3:

    a.  Install dependencies.

            mpbb install-dependencies \
                --prefix /opt/local \
                --port "$subport"

    b.  Install the subport itself.

            mpbb install-port --prefix /opt/local --port "$subport"

    c.  Gather archives.

            mpbb gather-archives \
                --prefix /opt/local \
                --port "$port" \
                --workdir "$workdir" \
                --archive-site "$archive_site" \
                --staging-dir "$(pwd)/archive-staging"

    d.  Upload. Must be implemented in the buildmaster.

    e.  Deploy. Must be implemented in the buildmaster.

    f.  Clean up. This must always be run, even if a previous step
        failed.

            mpbb cleanup --prefix /opt/local


## Step Implementation API ##

Step provider scripts are sourced and should provide a number of functions:

-   `$command`:
      Run the actual command.
-   `help`:
      Should print a help message to stderr. Does not need to deal with
      ending the execution.

Some shell variables are available for usage in your subcommand:

-   `$command`:
      is the name of the subcommand
-   `$option_archive_site`:
      is the URL to the packages archive that will be used
      to check for existing uploaded packages.
-   `$option_port`:
      is the port that should be installed in the run of mpbb.
-   `$option_prefix`:
      is the path to the MacPorts installation to use, as passed
      with --prefix.
-   `$option_staging_dir`:
      is the folder where archives that are distributable
      and should be upload must be put.
-   `$option_svn`:
      is the path to the svn binary to use.
-   `$option_svn_revision`:
      is the revision number to checkout in the given
      Subversion repository.
-   `$option_svn_url`:
      is a URL pointing to a Subversion repository that
      contains the dports and base subdirectories.
-   `$option_workdir`:
      is a path to a directory that can be used to store
      temporary data. This data is retained between builds. You can, for
      example, store a Subversion checkout there.
