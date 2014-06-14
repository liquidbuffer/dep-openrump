#!/bin/bash
# bash script for building and installing all dependencies locally
# by TheComet

# report uninitialised variables
set -u

###############################################################################
# get installation prefix
###############################################################################

# default installation prefix
if [[ -z "$1" ]]
then
	INSTALL_PREFIX="$(pwd)/dep"

	echo "  Installation prefix not set, defaulting installation path to:"
	echo "  $INSTALL_PREFIX"
	echo "  Is this ok? (enter '1' or '2')"
	select yn in "Yes" "No"
	do
		case $yn in
			Yes ) break;;
			No ) exit;;
		esac
	done

# installation prefix is specified
else
	if [[ "$1" = /* ]]
	then
		INSTALL_PREFIX="$1"
	else
		INSTALL_PREFIX="$(pwd)/$1"
	fi

	echo "  Installation prefix set to:"
	echo "  $INSTALL_PREFIX"
	echo "  Is this ok? (enter '1' or '2')"
	select yn in "Yes" "No"
	do
		case $yn in
			Yes ) break;;
			No ) exit;;
		esac
	done
fi

###############################################################################
# prepare
###############################################################################

# read previous installation directory and determine if bootstrap/configure
# process needs to be repeated
DO_CONFIGURE=true
if [ -e "last-build" ]
then
	read -r firstline<last-build
	if [ "$firstline" = "$1" ]
	then
		DO_CONFIGURE=false
	fi
fi
echo "$1" >last-build

# build temp directory
if [ ! -d "build" ]
then
	mkdir "build"
fi

# test commands
# TODO

# custom install prefix
export CPPFLAGS="-I$INSTALL_PREFIX/include"
export LDFLAGS="-L$INSTALL_PREFIX/lib"

# custom toolchain
if [ ! -z "$2" ] && [ ! -z "$3" ]
then
	export CC="$2"
	export CXX="$3"
fi


cd "build"

# extracts the archive if the extracted directory doesn't exist, then enters
# the new directory with 'cd'
#    $1 = archive name
#    $2 = extracted directory name
function extract_archive {

	# get archive extension
	FILE_NAME=$(basename "$1")
	FILE_EXTENSION="${FILE_NAME##*.}"
	case "$FILE_EXTENSION" in
		xz)	EXTRACT_COMMAND="tar --xz -xf";;
		bz2)	EXTRACT_COMMAND="tar --bzip2 -xf";;
		gz)	EXTRACT_COMMAND="tar --gzip -xf";;
		tgz)	EXTRACT_COMMAND="tar --gzip -xf";;
		zip)	EXTRACT_COMMAND="unzip";;
		*)	echo "Error: Unknown archive"; exit 1;;
	esac

	# extract
	if [ ! -d "$2" ]
	then
		eval "$EXTRACT_COMMAND $1"
		if [ $? -ne 0 ]
		then
			exit 1
		fi
	fi
}

# bootstraps a libtool build
function build_gnu_bootstrap {

	# do bootstrap if required
	if [ "$DO_CONFIGURE" = true ] && [ -e "bootstrap" ]
	then
		chmod +x bootstrap
		./bootstrap
		if [ $? -ne 0 ]
		then
			exit 1
		fi
	fi
}

# configure a libtool build
function build_gnu_configure {

	# do configure if required
	if [ "$DO_CONFIGURE" = true ] && [ -e "configure" ]
	then
		chmod +x configure
		if [ -z "$1" ]
		then
			./configure "--prefix=$INSTALL_PREFIX"
		else
			./configure "--prefix=$INSTALL_PREFIX" "$1"
		fi
		if [ $? -ne 0 ]
		then
			exit 1
		fi
		PREFIX_IN_CONFIGURE=true
	fi
}

# use gnu make and install
function build_gnu_make_install {
	make
	if [ $? -ne 0 ]
	then
		exit 1
	fi
	if [ "$PREFIX_IN_CONFIGURE" ]
	then
		make install
	else
		make install DESTDIR="$INSTALL_PREFIX"
	fi
	if [ $? -ne 0 ]
	then
		exit 1
	fi

}

# builds the archive assuming autotools
#    $1 = archive name
#    $2 = extracted directory name
function build_gnu {
	extract_archive "$1" "$2"
	cd "$2"
	PREFIX_IN_CONFIGURE=false

	build_gnu_bootstrap
	build_gnu_configure
	build_gnu_make_install

	cd ..
}

# builds the archive assuming cmake
#    $1 = archive name
#    $2 = extracted directory name
function build_cmake {
	extract_archive "$1" "$2"
	cd "$2"

	# configure if required
	if [ ! -d "build.gnu" ] || [ "$DO_CONFIGURE" = true ]
	then
		mkdir "build.gnu"
		cd "build.gnu"
		cmake -G "Unix Makefiles" -DCMAKE_PREFIX_PATH="$INSTALL_PREFIX" -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" .. -DCMAKE_BUILD_TYPE=Release
		if [ $? -ne 0 ]
		then
			exit 1
		fi
	else
		cd "build.gnu"
	fi

	# build and install
	make
	if [ $? -ne 0 ]
	then
		exit 1
	fi
	make install
	if [ $? -ne 0 ]
	then
		exit 1
	fi
	cd ../..
}

# builds the archive assuming bjam
#    $1 = archive name
#    $2 = extracted directory name
function build_bjam {
	extract_archive "$1" "$2"
	cd "$2"

	# bootstrap if required
	if [ ! -e "b2" ] || [ "$DO_CONFIGURE" = true ]
	then
		if [ -z "$CC" ]
		then
			./bootstrap.sh --prefix="$INSTALL_PREFIX"
		else
			./bootstrap.sh --prefix="$INSTALL_PREFIX" --with-toolset="$CC"
		fi
		if [ $? -ne 0 ]
		then
			exit 1
		fi
	fi

	# build
	./b2 install
	cd ..
}

# builds boost
#    $1 = archive name
#    $2 = extracted directory name
function build_boost {
	# boost requires a user-config.jam file located in the user's HOME directory
	# describing where python is located.
	echo "import toolset : using ;\nusing python\n\t: 2.7\n\t: $INSTALL_PREFIX\n\t;" >~/user-config.jam
	build_bjam "$1" "$2"
	rm ~/user-config.jam
}

# builds python
#    $1 = archive name
#    $2 = extracted directory name
function build_python {
	extract_archive "$1" "$2"
	cd "$2"
	PREFIX_IN_CONFIGURE=false

	build_gnu_bootstrap
	build_gnu_configure "--enable-shared"
	build_gnu_make_install

	cd ..

}

build_python "../packages/Python-2.7.7.tgz" "Python-2.7.7"
build_gnu "../packages/zlib-1.2.8.tar.xz" "zlib-1.2.8"
build_gnu "../packages/zziplib-0.13.59.tar.bz2" "zziplib-0.13.59"
build_gnu "../packages/FreeImage3160.zip" "FreeImage"
build_gnu "../packages/freetype-2.5.3.tar.bz2" "freetype-2.5.3"
build_gnu "../packages/ois-v1-3.tar.gz" "ois-v1-3"
build_cmake "../packages/bullet-2.82-r2704.tgz" "bullet-2.82-r2704"
build_boost "../packages/boost_1_55_0.tar.bz2" "boost_1_55_0"
build_cmake "../packages/ogre_1-9-0.tar.xz" "ogre_1-9-0"

echo "DONE!"

exit 0
