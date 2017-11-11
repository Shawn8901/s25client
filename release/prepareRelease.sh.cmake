#!/bin/bash

# Editable Variables
CMAKE_COMMAND=cmake

###############################################################################

if [ -z "$(type -p $CMAKE_COMMAND)" ] ; then
	echo "You have to install CMake" >&2
	exit 1
fi

###############################################################################

mecho()
{
	COLOR=$1
	shift
	$CMAKE_COMMAND -E cmake_echo_color --bold $COLOR "$*"
}

###############################################################################

SYSTEM_NAME=@CMAKE_SYSTEM_NAME@
SYSTEM_ARCH=@PLATFORM_ARCH@
IS_CROSS_COMPILE=@CMAKE_CROSSCOMPILING@
RTTR_BINDIR=@RTTR_BINDIR@
RTTR_DATADIR=@RTTR_DATADIR@
RTTR_LIBDIR=@RTTR_LIBDIR@
RTTR_DRIVERDIR=@RTTR_DRIVERDIR@

RTTR_SRCDIR=@RTTR_SRCDIR@

if [ -z "${RTTR_SRCDIR}" ] ; then
	echo "RTTR_SRCDIR was not set" >&2
	exit 1
fi

echo "## Installing for \"${SYSTEM_NAME}\""
echo "## Using Binary Dir \"${RTTR_BINDIR}\""
echo "## Using Data Dir \"${RTTR_DATADIR}\""
echo "## Using Library Dir \"${RTTR_LIBDIR}\""

###############################################################################

# strip ending slash from $DESTDIR
DESTDIR=${DESTDIR%/}

# adding the slash again if DESTDIR is not empty
if [ ! -z "$DESTDIR" ] ; then
	DESTDIR=${DESTDIR}/
	mecho --red "## Using Destination Dir \"${DESTDIR}\""
fi

###############################################################################

mecho --blue "## Removing files which are unused (but installed by cmake)"
rm -vf ${DESTDIR}${RTTR_DRIVERDIR}/video/libvideo*.{a,lib}
rm -vf ${DESTDIR}${RTTR_DRIVERDIR}/audio/libaudio*.{a,lib}

extract_debug_symbols()
{
	local FILE=$1

	objcopyArch=""
	case "$SYSTEM_ARCH" in
		i686|*86)
			objcopyArch="i686"
		;;
		x86_64|*64)
			objcopyArch="x86_64"
		;;
		powerpc|ppc)
			objcopyArch="powerpc"
		;;
		*)
			echo "$SYSTEM_ARCH not supported" >&2
			return 1
		;;
	esac

	objcopyTarget=""
	case "$SYSTEM_NAME" in
		Windows)
			objcopyTarget="-pc-mingw32"
		;;
		Linux)
			objcopyTarget="-pc-linux-gnu"
		;;
		FreeBSD)
			objcopy="objcopy"  # no cross-build support for FreeBSD
		;;
		*)
			echo "$SYSTEM_NAME not supported" >&2
			return 1
		;;
	esac

	# Set if not yet set
	: ${objcopy:=${objcopyArch}${objcopyTarget}-objcopy}

	if ! `${objcopy} -V >/dev/null 2>&1`; then
		# Use fallback
		case "$SYSTEM_NAME" in
			Windows)
				objcopyTarget="-mingw32"
			;;
			Linux)
				objcopyTarget="-linux-gnu"
			;;
		esac
		objcopy="${objcopyArch}${objcopyTarget}-objcopy"
	fi

	pushd ${DESTDIR}
	mkdir -vp dbg/$(dirname $FILE)
	echo "${objcopy} --only-keep-debug $FILE dbg/$FILE.dbg"
	${objcopy} --only-keep-debug $FILE dbg/$FILE.dbg
	echo "${objcopy} --strip-debug $FILE"
	${objcopy} --strip-debug $FILE
	echo "${objcopy} --add-gnu-debuglink=dbg/$FILE.dbg $FILE"
	${objcopy} --add-gnu-debuglink=dbg/$FILE.dbg $FILE
	popd
}

mecho --blue "## Extracting debug info from files and saving them into dbg"

# strip out debug symbols into external file
case "$SYSTEM_NAME" in
	Darwin)
		echo "extraction of debug symbols for Apple currently not supported" >&2
		STRIP=@CMAKE_STRIP@
		$STRIP -S ${DESTDIR}bin/s25client
		$STRIP -S ${DESTDIR}bin/s25edit
		$STRIP -S ${DESTDIR}lib/share/s25rttr/driver/video/libvideoSDL.dylib
		$STRIP -S ${DESTDIR}lib/share/s25rttr/driver/audio/libaudioSDL.dylib
		$STRIP -S ${DESTDIR}bin/RTTR/s25update
		$STRIP -S ${DESTDIR}bin/RTTR/sound-convert
		$STRIP -S ${DESTDIR}bin/RTTR/s-c_resample
	;;
	Windows)
		extract_debug_symbols s25client.exe
		extract_debug_symbols s25edit.exe
		extract_debug_symbols driver/video/libvideoWinAPI.dll
		extract_debug_symbols driver/video/libvideoSDL.dll
		extract_debug_symbols driver/audio/libaudioSDL.dll
		extract_debug_symbols RTTR/s25update.exe
		extract_debug_symbols RTTR/sound-convert.exe
		extract_debug_symbols RTTR/s-c_resample.exe
	;;
	Linux|FreeBSD)
		extract_debug_symbols bin/s25client
		extract_debug_symbols bin/s25edit
		extract_debug_symbols share/s25rttr/driver/video/libvideoSDL.so
		extract_debug_symbols share/s25rttr/driver/audio/libaudioSDL.so
		extract_debug_symbols bin/RTTR/s25update
		extract_debug_symbols bin/RTTR/sound-convert
		extract_debug_symbols bin/RTTR/s-c_resample
	;;
	*)
		echo "$SYSTEM_NAME not supported" >&2
		exit 1
	;;
esac

mecho --blue "## Performing additional tasks"

case "$SYSTEM_NAME" in
	Darwin)
		# create app-bundle for apple
		# app anlegen
		mkdir -vp ${DESTDIR}s25client.app/Contents/{MacOS,Resources} || exit 1

		# frameworks kopieren
		mkdir -vp ${DESTDIR}s25client.app/Contents/MacOS/Frameworks || exit 1
		mkdir -vp ${DESTDIR}s25client.app/Contents/MacOS/Frameworks/{SDL,SDL_mixer}.framework || exit 1

		if [ -d /Library/Frameworks ] ; then
			cp -r /Library/Frameworks/SDL.framework ${DESTDIR}s25client.app/Contents/MacOS/Frameworks || exit 1
			cp -r /Library/Frameworks/SDL_mixer.framework ${DESTDIR}s25client.app/Contents/MacOS/Frameworks || exit 1
		else
			cp -r /usr/lib/apple/SDKs/Library/Frameworks/SDL.framework ${DESTDIR}s25client.app/Contents/MacOS/Frameworks || exit 1
			cp -r /usr/lib/apple/SDKs/Library/Frameworks/SDL_mixer.framework ${DESTDIR}s25client.app/Contents/MacOS/Frameworks || exit 1
		fi

		# remove headers and additional libraries from the frameworks
		find ${DESTDIR}s25client.app/Contents/MacOS/Frameworks/ -name Headers -exec rm -rf {} \;
		find ${DESTDIR}s25client.app/Contents/MacOS/Frameworks/ -name Resources -exec rm -rf {} \;

		SDK=@CMAKE_OSX_SYSROOT@

		# copy libs
		for LIBSUFFIX in miniupnpc.16 miniupnpc.2.0 boost_system boost_filesystem boost_iostreams boost_thread boost_locale boost_program_options ; do
			LIB=/usr/lib/lib${LIBSUFFIX}.dylib
			if [ -f $SDK$LIB ] ; then
				cp -rv $SDK$LIB ${DESTDIR}s25client.app/Contents/MacOS || exit 1
			else
				echo "$LIB was not found in $SDK" >&2
				exit 1
			fi
		done

		mkdir -vp ${DESTDIR}s25client.app/Contents/MacOS/bin || exit 1
		mkdir -vp ${DESTDIR}s25client.app/Contents/MacOS/lib || exit 1

		# binaries und paketdaten kopieren
		cp -v ${RTTR_SRCDIR}/release/bin/macos/rttr.command ${DESTDIR}s25client.app/Contents/MacOS/ || exit 1
		cp -v ${RTTR_SRCDIR}/release/bin/macos/rttr.terminal ${DESTDIR}s25client.app/Contents/MacOS/ || exit 1
		cp -v ${RTTR_SRCDIR}/release/bin/macos/icon.icns ${DESTDIR}s25client.app/Contents/Resources/ || exit 1
		cp -v ${RTTR_SRCDIR}/release/bin/macos/PkgInfo ${DESTDIR}s25client.app/Contents/ || exit 1
		cp -v ${RTTR_SRCDIR}/release/bin/macos/Info.plist ${DESTDIR}s25client.app/Contents/ || exit 1
		mv -v ${DESTDIR}bin/* ${DESTDIR}s25client.app/Contents/MacOS/bin/ || exit 1
		mv -v ${DESTDIR}lib/* ${DESTDIR}s25client.app/Contents/MacOS/lib/ || exit 1
		
		chmod +x ${DESTDIR}s25client.app/Contents/MacOS/* || exit 1

		# remove dirs if empty
		rmdir ${DESTDIR}bin
		rmdir ${DESTDIR}lib

		# RTTR-Ordner kopieren
		mv -v ${DESTDIR}share ${DESTDIR}s25client.app/Contents/MacOS/ || exit 1
	;;
	Windows)
		mingw=/usr
		lua=""
		case "$SYSTEM_ARCH" in
			i686|*86)
				if [ -d /usr/i686-pc-mingw32 ]; then
					mingw=/usr/i686-pc-mingw32
				else
					mingw=/usr/i686-mingw32
				fi
				lua=win32
			;;
			x86_64|*64)
				if [ -d /usr/i686-pc-mingw32 ]; then
					mingw=/usr/x86_64-pc-mingw32
				else
					mingw=/usr/x86_64-mingw32
				fi
				lua=win64
			;;
		esac
		
		cp -v ${RTTR_SRCDIR}/contrib/lua/${lua}/lua52.dll ${DESTDIR} || exit 1
		cp -v ${mingw}/bin/libgcc_s_sjlj-1.dll ${DESTDIR} || exit 1
		cp -v ${mingw}/bin/libminiupnpc-5.dll ${DESTDIR} || exit 1
		cp -v ${mingw}/bin/libiconv-2.dll ${DESTDIR} || exit 1
		cp -v ${mingw}/bin/libintl-8.dll ${DESTDIR} || exit 1
		cp -v ${mingw}/bin/libogg-0.dll ${DESTDIR} || exit 1
		cp -v ${mingw}/bin/SDL_mixer.dll ${DESTDIR} || exit 1
		cp -v ${mingw}/bin/SDL.dll ${DESTDIR} || exit 1
		cp -v ${mingw}/bin/libvorbis-0.dll ${DESTDIR} || exit 1
		cp -v ${mingw}/bin/libvorbisfile-3.dll ${DESTDIR} || exit 1
		
		cp -v ${mingw}/bin/libgcc_s_sjlj-1.dll ${DESTDIR}RTTR || exit 1
		cp -v ${mingw}/bin/libcurl-4.dll ${DESTDIR}RTTR || exit 1
		cp -v ${mingw}/bin/zlib1.dll ${DESTDIR}RTTR || exit 1

		rmdir --ignore-fail-on-non-empty -v ${DESTDIR}S2
	;;
	Linux)
		miniupnpc=/usr/lib/libminiupnpc.so
		case "$SYSTEM_ARCH" in
			i686|*86)
				if [ "${IS_CROSS_COMPILE}" = "TRUE" ] ; then
					miniupnpc=/usr/i686-pc-linux-gnu/lib/libminiupnpc.so
				elif [ ! -f $miniupnpc ]; then
					# Use fallback
					miniupnpc=/usr/lib/i686-linux-gnu/libminiupnpc.so
				fi
			;;
			x86_64|*64)
				if [ "${IS_CROSS_COMPILE}" = "TRUE" ] ; then
					miniupnpc=/usr/x86_64-pc-linux-gnu/lib/libminiupnpc.so
				elif [ ! -f $miniupnpc ]; then
					# Use fallback
					miniupnpc=/usr/lib/x86_64-linux-gnu/libminiupnpc.so
				fi
			;;
		esac

		if [ -f $miniupnpc ] ; then
			mkdir -p ${DESTDIR}/lib/ || exit 1
			cp -rv $miniupnpc* ${DESTDIR}/lib/ || exit 1
		else
			echo "libminiupnpc.so not found at $miniupnpc" >&2
			echo "will not bundle it in your installation" >&2
			echo "install it via \"sudo apt-get install miniupnpc\"" >&2
		fi
	;;
	FreeBSD)
		miniupnpc=/usr/local/lib/libminiupnpc.so
		if [ -f $miniupnpc ] ; then
			mkdir -p ${DESTDIR}/lib/ || exit 1
			cp -rv ${miniupnpc}* ${DESTDIR}/lib/ || exit 1
		else
			echo "libminiupnpc.so not found at $miniupnpc" >&2
			echo "will not bundle it in your installation" >&2
			echo "install it via \"sudo pkg install miniupnpc\"" >&2
		fi
	;;
	*)
		echo "$SYSTEM_ARCH not supported" >&2
		exit 1
	;;
esac

exit 0

###############################################################################
