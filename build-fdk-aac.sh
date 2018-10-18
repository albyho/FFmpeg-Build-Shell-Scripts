#!/bin/sh

# set -e: 如果任何语句的执行结果不是true
set -e

# 源码目录和目标目录
SOURCE="fdk-aac-0.1.6"
FAT="fat-fdk-aac"

CONFIGURE_FLAGS="--enable-static --disable-shared  --with-pic=yes"

ARCHS="arm64 armv7 x86_64 i386"

SCRATCH="scratch-fdk-aac"
# 必须为绝对路径s
THIN=`pwd`/"thin-fdk-aac"

COMPILE="y"
LIPO="y"

BASE_SDK="10.4"
DEPLOYMENT_TARGET="8.0"
DEVELOPER=`xcode-select -print-path`

if [ "$*" ]
then
	if [ "$*" = "lipo" ]
	then
		# 跳过编译步骤
		COMPILE=
	else
		ARCHS="$*"
		if [ $# -eq 1 ]
		then
			# 跳过合并步骤
			LIPO=
		fi
	fi
fi

if [ "$COMPILE" ]
then
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
		    if [ "$ARCH" = "x86_64" ]
		    then
                HOST="--host=x86_64-apple-darwin"
		    else
                HOST="--host=i386-apple-darwin"
		    fi
            CFLAGS="$CFLAGS -mios-simulator-version-min=$DEPLOYMENT_TARGET"
		else
		    PLATFORM="iPhoneOS"
		    if [ $ARCH = arm64 ]
		    then
		        HOST="--host=aarch64-apple-darwin"
                    else
		        HOST="--host=arm-apple-darwin"
	        fi
            CFLAGS="$CFLAGS -mios-version-min=$DEPLOYMENT_TARGET"
		fi

        SDK_PATH="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer/SDKS/${PLATFORM}.sdk"
		LDFLAGS="$CFLAGS"
		CPPFLAGS="$CFLAGS"
		CXXFLAGS="$CFLAGS"
        CFLAGS="$CFLAGS -isysroot $SDK_PATH"

		XCRUN_SDK=`echo $PLATFORM | tr '[:upper:]' '[:lower:]'`
		CC="xcrun -sdk $XCRUN_SDK clang"

        CC=$CC \
		CFLAGS=$CFLAGS \
		LDFLAGS=$LDFLAGS \
		CPPFLAGS="$CPPFLAGS" \
		CXXFLAGS="$CXXFLAGS" \
		$CWD/$SOURCE/configure \
            $CONFIGURE_FLAGS \
            $HOST \
            --prefix="$THIN/$ARCH" 

		make -j4 install
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
		lipo -create `find $THIN -name $LIB` -output $FAT/lib/$LIB
	done

	cd $CWD
	cp -rf $THIN/$1/include $FAT
fi
