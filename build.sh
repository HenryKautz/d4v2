#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

set -e
set -u
set -o pipefail

opt=0

while getopts 'dsl' OPTION
do
    case "$OPTION" in
        d)
            opt=1
            ;;
        s)
            opt=2
            ;;
        p)
            opt=3
            ;;
    esac
done

# Build with the Homebrew GNU toolchain (g++-16/gcc-16) rather than Apple clang.
export CC=gcc-16
export CXX=g++-16

cd $SCRIPT_DIR/3rdParty/flowCutter
make -j DEBUG=$opt CC=g++-16

cd $SCRIPT_DIR/3rdParty/glucose-3.0/core/
make libst CXX=g++-16
mv lib_static.a lib_glucose.a

cd $SCRIPT_DIR/3rdParty/bipe/
./build.sh -s

cd $SCRIPT_DIR
mkdir -p build
cd build
# Unix Makefiles generator (Ninja is not required); force the Homebrew toolchain.
cmake -G "Unix Makefiles" .. -DBUILD_MODE=$opt \
      -DCMAKE_C_COMPILER=gcc-16 -DCMAKE_CXX_COMPILER=g++-16
make -j

# Merge everything into one libd4.a.  macOS ar lacks GNU ar's thin-archive (T) and
# MRI script (-M) modes, so use macOS libtool -static, which flattens the member
# archives' objects into a single static library.
mv libd4.a libd4tmp.a
libtool -static -o libd4.a libd4tmp.a ../3rdParty/flowCutter/libflowCutter.a ../3rdParty/patoh/libpatoh.a ../3rdParty/glucose-3.0/core/lib_glucose.a ../3rdParty/bipe/build/libbipe.a
