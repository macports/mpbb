#!/bin/sh
mkdir -p mpexport
svn checkout --non-interactive -r HEAD https://svn.macports.org/repository/macports/trunk/base mpexport/base
svn checkout --non-interactive -r HEAD https://svn.macports.org/repository/macports/trunk/dports mpexport/dports
cd mpexport
tar c --exclude '.svn' -f - . | bzip2 -c > ../macports_dist.tar.bz2
cd ..
