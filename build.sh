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

# On macOS, build with the Homebrew GNU toolchain (g++-16/gcc-16) rather than Apple
# clang, use the Unix Makefiles generator (Ninja not required), and merge static
# libs with libtool (macOS ar lacks GNU ar's thin-archive/MRI modes).  On Linux the
# original toolchain, Ninja, and GNU ar are used unchanged.
if [ "$(uname)" = "Darwin" ]; then
    export CC=gcc-16
    export CXX=g++-16
    FLOW_MAKE_ARGS="CC=g++-16"
    GLUCOSE_MAKE_ARGS="CXX=g++-16"
    CMAKE_GEN=(-G "Unix Makefiles" -DCMAKE_C_COMPILER=gcc-16 -DCMAKE_CXX_COMPILER=g++-16)
    CMAKE_BUILD=(make -j)

    # The demos link our g++ build of boost::program_options (3rdParty/boost_po)
    # but compile against Homebrew's Boost headers.  When Homebrew upgrades Boost
    # the two no longer match and the link fails with missing boost symbols, so
    # rebuild the library whenever the version it was built for differs.
    brew_boost=$(sed -n 's/^#define BOOST_VERSION \([0-9]*\).*/\1/p' \
                 "$(brew --prefix)/include/boost/version.hpp" 2>/dev/null || true)
    built_boost=$(cat "$SCRIPT_DIR/3rdParty/boost_po/BOOST_VERSION" 2>/dev/null || true)
    if [ -z "$brew_boost" ] || [ "$brew_boost" != "$built_boost" ]; then
        echo ">> 3rdParty/boost_po was built for Boost '${built_boost:-unknown}'," \
             "Homebrew has '${brew_boost:-none}': rebuilding it"
        "$SCRIPT_DIR/setup-macos-deps.sh" --boost-only
    fi
else
    FLOW_MAKE_ARGS=""
    GLUCOSE_MAKE_ARGS=""
    CMAKE_GEN=(-GNinja)
    CMAKE_BUILD=(ninja)
fi

cd $SCRIPT_DIR/3rdParty/flowCutter
make -j DEBUG=$opt $FLOW_MAKE_ARGS

cd $SCRIPT_DIR/3rdParty/glucose-3.0/core/
make libst $GLUCOSE_MAKE_ARGS
mv lib_static.a lib_glucose.a

cd $SCRIPT_DIR/3rdParty/bipe/
./build.sh -s

cd $SCRIPT_DIR
mkdir -p build
cd build
cmake "${CMAKE_GEN[@]}" .. -DBUILD_MODE=$opt
"${CMAKE_BUILD[@]}"

# make a library of everything
mv libd4.a libd4tmp.a
if [ "$(uname)" = "Darwin" ]; then
    libtool -static -o libd4.a libd4tmp.a ../3rdParty/flowCutter/libflowCutter.a ../3rdParty/patoh/libpatoh.a ../3rdParty/glucose-3.0/core/lib_glucose.a ../3rdParty/bipe/build/libbipe.a
else
    ar cqT libd4.a libd4tmp.a ../3rdParty/flowCutter/libflowCutter.a ../3rdParty/patoh/libpatoh.a ../3rdParty/glucose-3.0/core/lib_glucose.a ../3rdParty/bipe/build/libbipe.a && echo -e 'create libd4.a\naddlib libd4.a\nsave\nend' | ar -M
fi
