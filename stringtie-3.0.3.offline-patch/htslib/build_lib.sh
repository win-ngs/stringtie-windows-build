#!/usr/bin/env bash
##
if [[ "$1" == "clean" ]]; then
  make clean
  /bin/rm -f config.h
  /bin/rm -rf xlibs
  exit
fi

pwd=$(pwd -P)
prefix=$pwd/xlibs
incdir=$prefix/include
libdir=$prefix/lib
mkdir -p $incdir $libdir
cc=${CC:-gcc}
cxx=${CXX:-g++}

if [[ ! -d libdeflate ]]; then
  echo "Error: libdeflate source not found!"
  exit 1
fi
if [[ ! -f $libdir/libdeflate.a ]]; then
  cd libdeflate
  MINGW=''
  libdeflate=libdeflate.a
  if [[ $($cc -dumpmachine 2>/dev/null) == *mingw* ]]; then
   MINGW=1
   libdeflate=libdeflatestatic.lib
  fi
  make -f ../Makefile.libdeflate -j 4 $libdeflate CC="$cc" CXX="$cxx" || exit 1
  cp $libdeflate $libdir/libdeflate.a
  cp libdeflate.h $incdir/
  cd ..
fi

if [[ ! -d bzip2 ]]; then
  echo "Error: bzip2 source not found!"
  exit 1
fi
if [[ ! -f $libdir/libbz2.a ]]; then
  cd bzip2
  make -j 4 libbz2.a CC="$cc"
  cp bzlib.h $incdir/
  cp libbz2.a $libdir/
  cd ..
fi

if [[ ! -d lzma ]]; then
  echo "Error: lzma source not found!"
  exit 1
fi
if [[ ! -f $libdir/liblzma.a ]]; then
  cd lzma
  CC="$cc" CXX="$cxx" ./configure --disable-shared -disable-xz -disable-xzdec --disable-lzmadec \
   --disable-lzmainfo --disable-nls --prefix=$prefix
  make -j 4 CC="$cc" CXX="$cxx"
  make install CC="$cc" CXX="$cxx"
  cd ..
fi

make -j 4 CC="$cc" CXX="$cxx" lib-static
