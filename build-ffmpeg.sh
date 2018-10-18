#!/bin/sh

set -e

# directories
SOURCE="ffmpeg-4.0.2"
FAT="fat-ffmpeg"

SCRATCH="scratch-ffmpeg"
# must be an absolute path
THIN=`pwd`/"thin-ffmpeg"

# absolute path to x264 library
X264=`pwd`/fat-x264

LAME=`pwd`/fat-lame

FDK_AAC=`pwd`/fat-fdk-aac

CONFIGURE_FLAGS="--enable-cross-compile --target-os=darwin --enable-gpl --enable-version3 --enable-nonfree \
                 --disable-debug --disable-programs  --disable-doc --disable-everything \
                 --disable-network --disable-avdevice \
                 --disable-armv5te  --disable-armv6 --disable-armv6t2 \
                 --disable-zlib --disable-bzlib \
                 --disable-shared \
                 --enable-static \
                 --enable-protocol=file \
                 --enable-decoder=aac   --enable-parser=aac \
                 --enable-decoder=mp3 \
                 --enable-decoder=h264  --enable-parser=h264 \
                 --enable-muxer=mp4     --enable-muxer=mp3 --enable-muxer=h264 --enable-muxer=mov --enable-muxer=m4v\
                 --enable-demuxer=aac --enable-demuxer=mp3 --enable-demuxer=h264 --enable-demuxer=mov --enable-demuxer=m4v \
"

# i386, x86_64
CONFIGURE_FLAGS_SIMULATOR=
CONFIGURE_FLAGS_SIMULATOR="$CONFIGURE_FLAGS_SIMULATOR --disable-asm"
CONFIGURE_FLAGS_SIMULATOR="$CONFIGURE_FLAGS_SIMULATOR --disable-mmx"
CONFIGURE_FLAGS_SIMULATOR="$CONFIGURE_FLAGS_SIMULATOR --assert-level=2"

# armv7, arm64
CONFIGURE_FLAGS_ARM=
CONFIGURE_FLAGS_ARM="$CONFIGURE_FLAGS_ARM --enable-pic"
CONFIGURE_FLAGS_ARM="$CONFIGURE_FLAGS_ARM --enable-asm"
CONFIGURE_FLAGS_ARM="$CONFIGURE_FLAGS_ARM --enable-neon"
CONFIGURE_FLAGS_ARM="$CONFIGURE_FLAGS_ARM --enable-optimizations"
CONFIGURE_FLAGS_ARM="$CONFIGURE_FLAGS_ARM --enable-small"
CONFIGURE_FLAGS_ARM="$CONFIGURE_FLAGS_ARM --disable-debug"

if [ "$X264" ]
then
	CONFIGURE_FLAGS="$CONFIGURE_FLAGS --enable-libx264 --enable-encoder=libx264 --enable-encoder=libx264rgb"
fi

if [ "$LAME" ]
then
    CONFIGURE_FLAGS="$CONFIGURE_FLAGS --enable-libmp3lame --enable-encoder=libmp3lame"
fi

if [ "$FDK_AAC" ]
then
CONFIGURE_FLAGS="$CONFIGURE_FLAGS --enable-libfdk-aac --enable-encoder=libfdk_aac"
fi

ARCHS="arm64 armv7 x86_64 i386"

COMPILE="y"
LIPO="y"

BASE_SDK="10.4"
DEPLOYMENT_TARGET="8.0"
DEVELOPER=`xcode-select -print-path`

if [ "$*" ]
then
	if [ "$*" = "lipo" ]
	then
		# skip compile
		COMPILE=
	else
		ARCHS="$*"
		if [ $# -eq 1 ]
		then
			# skip lipo
			LIPO=
		fi
	fi
fi

if [ "$COMPILE" ]
then
	if [ ! `which yasm` ]
	then
		echo 'Yasm not found'
		if [ ! `which brew` ]
		then
			echo 'Homebrew not found. Trying to install...'
			ruby -e "$(curl -fsSL https://raw.github.com/Homebrew/homebrew/go/install)" \
				|| exit 1
		fi
		echo 'Trying to install Yasm...'
		brew install yasm || exit 1
	fi
	if [ ! `which gas-preprocessor.pl` ]
	then
		echo 'gas-preprocessor.pl not found. Trying to install...'
		(curl -L https://raw.githubusercontent.com/FFmpeg/gas-preprocessor/master/gas-preprocessor.pl \
			-o /usr/local/bin/gas-preprocessor.pl \
			&& chmod +x /usr/local/bin/gas-preprocessor.pl) \
			|| exit 1
	fi

	if [ ! -r $SOURCE ]
	then
		echo 'FFmpeg source not found. Trying to download...'
		curl http://www.ffmpeg.org/releases/$SOURCE.tar.bz2 | tar xj \
			|| exit 1
	fi

	CWD=`pwd`
	for ARCH in $ARCHS
	do
		echo "building $ARCH..."
		mkdir -p "$SCRATCH/$ARCH"
		cd "$SCRATCH/$ARCH"

        CFLAGS="-arch $ARCH"
        CFLAGS="$CFLAGS -fembed-bitcode"

		if [ "$ARCH" = "i386" -o "$ARCH" = "x86_64" ]
		then
		    PLATFORM="iPhoneSimulator"            
		    EXTRA_FLAGS="$CONFIGURE_FLAGS_SIMULATOR"
		    CFLAGS="$CFLAGS -mios-simulator-version-min=$DEPLOYMENT_TARGET"
		else
		    PLATFORM="iPhoneOS"
            EXTRA_FLAGS="$CONFIGURE_FLAGS_ARM"
            CFLAGS="$CFLAGS -mios-version-min=$DEPLOYMENT_TARGET -mfpu=neon"
		    if [ "$ARCH" = "arm64" ]
		    then
		        EXPORT="GASPP_FIX_XCODE5=1"
		    fi
		fi

		SDK_PATH="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer/SDKS/${PLATFORM}.sdk"
		CXXFLAGS="$CFLAGS"
		LDFLAGS="$CFLAGS"
		CFLAGS="$CFLAGS -isysroot $SDK_PATH"

		XCRUN_SDK=`echo $PLATFORM | tr '[:upper:]' '[:lower:]'`
		CC="xcrun -sdk $XCRUN_SDK clang"

		if [ "$X264" ]
		then
			CFLAGS="$CFLAGS -I$X264/include"
			LDFLAGS="$LDFLAGS -L$X264/lib"
		fi
		if [ "$FDK_AAC" ]
		then
			CFLAGS="$CFLAGS -I$FDK_AAC/include"
			LDFLAGS="$LDFLAGS -L$FDK_AAC/lib"
		fi
        if [ "$LAME" ]
        then
            CFLAGS="$CFLAGS -I$LAME/include"
            LDFLAGS="$LDFLAGS -L$LAME/lib"
        fi

		TMPDIR=${TMPDIR/%\/} $CWD/$SOURCE/configure \
		    --target-os=darwin \
		    --arch=$ARCH \
		    --cc="$CC" \
		    $CONFIGURE_FLAGS \
            $EXTRA_FLAGS \
		    --extra-cflags="$CFLAGS" \
		    --extra-cxxflags="$CXXFLAGS" \
		    --extra-ldflags="$LDFLAGS" \
		    --prefix="$THIN/$ARCH" \
		|| exit 1

		make -j4 install $EXPORT || exit 1
		cd $CWD
	done
fi

if [ "$LIPO" ]
then
	echo "building fat binaries..."
	mkdir -p $FAT/lib
	set - $ARCHS
	CWD=`pwd`
	cd $THIN/$1/lib
	for LIB in *.a
	do
		cd $CWD
		echo lipo -create `find $THIN -name $LIB` -output $FAT/lib/$LIB 1>&2
		lipo -create `find $THIN -name $LIB` -output $FAT/lib/$LIB || exit 1
	done

	cd $CWD
	cp -rf $THIN/$1/include $FAT
	
	if [ "$X264" ]
	then
		cp -f $X264/include/*.h $FAT/include
		cp -f $X264/lib/*.a $FAT/lib
	fi
	if [ "$FDK_AAC" ]
	then
		cp -f $FDK_AAC/include/fdk-aac/*.h $FAT/include
		cp -f $FDK_AAC/lib/*.a $FAT/lib
	fi
    if [ "$LAME" ]
    then
        cp -f $LAME/include/lame/*.h $FAT/include
        cp -f $LAME/lib/*.a $FAT/lib
    fi

fi

echo Done
