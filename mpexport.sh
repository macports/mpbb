#/bin/sh
svn checkout -r HEAD http://svn.macports.org/repository/macports/trunk mpexport
cd mpexport
tar c --exclude '.svn' -f - . | bzip2 -c > ../macports_dist.tar.bz2
cd ..
