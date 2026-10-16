#!/bin/bash
#
# setup-macos-deps.sh -- fetch/build the two dependencies that are NOT bundled in
# this repository, so d4 can be built on macOS with the Homebrew GNU toolchain.
#
#   1. PaToH static library.  PaToH is closed-source and its license forbids
#      redistribution, so no libpatoh.a is checked in.  Georgia Tech publishes a
#      native macOS (arm64 and x86_64) build; this script downloads the one for
#      your architecture and installs libpatoh.a + patoh.h into 3rdParty/patoh/.
#
#   2. boost::program_options built with g++ (libstdc++).  Homebrew's
#      libboost_program_options.a is built with Apple clang/libc++ and is
#      ABI-incompatible with a g++ (libstdc++) build, so the demo fails to link
#      against it.  This script compiles program_options from the matching Boost
#      source with the same g++ used for d4, into 3rdParty/boost_po/.
#
# Prerequisites (Homebrew):  brew install gcc gmp boost cmake
#
# Usage:   ./setup-macos-deps.sh        then    ./build.sh
#          ./setup-macos-deps.sh --boost-only   (step 2 only; build.sh runs this
#          itself when Homebrew's Boost no longer matches 3rdParty/boost_po)
# Override the compiler with e.g.:  CXX=g++-15 ./setup-macos-deps.sh

set -euo pipefail
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
CXX=${CXX:-g++-16}
boost_only=0
case "${1:-}" in
  "")           ;;
  --boost-only) boost_only=1 ;;
  *)            echo "usage: $0 [--boost-only]" >&2; exit 2 ;;
esac

die() { echo "setup-macos-deps.sh: $1" >&2; exit 1; }

# --- prerequisites ----------------------------------------------------------
command -v "$CXX"   >/dev/null 2>&1 || die "Homebrew GCC not found ($CXX). Run: brew install gcc  (or set CXX=g++-NN)"
command -v cmake    >/dev/null 2>&1 || die "cmake not found. Run: brew install cmake"
command -v brew     >/dev/null 2>&1 || die "Homebrew not found."
BREW=$(brew --prefix)
[ -d "$BREW/include/boost" ] || die "boost headers not found under $BREW/include. Run: brew install boost"
[ -e "$BREW/include/gmp.h" ] || die "gmp not found under $BREW/include. Run: brew install gmp"

# --- 1. PaToH ---------------------------------------------------------------
if [ "$boost_only" = 0 ]; then
ARCH=$(uname -m)
case "$ARCH" in
  arm64)  PATOH_TGZ=patoh-Darwin-arm64.tar.gz ;;
  x86_64) PATOH_TGZ=patoh-Darwin-x86_64.tar.gz ;;
  *)      die "unsupported macOS architecture: $ARCH" ;;
esac
echo ">> [1/2] Downloading PaToH for $ARCH ($PATOH_TGZ) ..."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/$PATOH_TGZ" "https://faculty.cc.gatech.edu/~umit/PaToH/$PATOH_TGZ" \
  || die "could not download PaToH (see https://faculty.cc.gatech.edu/~umit/software.html)"
tar xzf "$tmp/$PATOH_TGZ" -C "$tmp"
lib=$(find "$tmp" -name libpatoh.a | head -1)
[ -n "$lib" ] || die "libpatoh.a not found in the PaToH archive"
src=$(dirname "$lib")
cp "$src/libpatoh.a" "$SCRIPT_DIR/3rdParty/patoh/libpatoh.a"
cp "$src/patoh.h"    "$SCRIPT_DIR/3rdParty/patoh/patoh.h"
echo "   installed 3rdParty/patoh/{libpatoh.a,patoh.h}  ($(lipo -info "$SCRIPT_DIR/3rdParty/patoh/libpatoh.a" 2>/dev/null | sed 's/.*: //'))"
fi

# --- 2. boost::program_options (built with g++) -----------------------------
bv=$(sed -n 's/^#define BOOST_VERSION \([0-9]*\).*/\1/p' "$BREW/include/boost/version.hpp")
[ -n "$bv" ] || die "could not read BOOST_VERSION from $BREW/include/boost/version.hpp"
maj=$(( bv / 100000 )); min=$(( bv / 100 % 1000 )); pat=$(( bv % 100 ))
TAG="boost-${maj}.${min}.${pat}"
echo ">> [2/2] Building boost::program_options ($TAG) with $CXX (libstdc++) ..."
po="$SCRIPT_DIR/3rdParty/boost_po"
mkdir -p "$po/src"
base="https://raw.githubusercontent.com/boostorg/program_options/${TAG}/src"
# Every program_options source file except winmain.cpp (Windows only).
for f in cmdline config_file convert options_description parsers \
         positional_options split utf8_codecvt_facet value_semantic variables_map; do
  curl -fsSL -o "$po/src/$f.cpp" "$base/$f.cpp" \
    || die "could not download program_options/$f.cpp at $TAG"
done
(
  cd "$po"
  rm -f ./*.o libboost_program_options.a BOOST_VERSION
  for f in src/*.cpp; do
    "$CXX" -std=c++20 -O2 -fPIC -I"$BREW/include" -c "$f" -o "$(basename "${f%.cpp}").o"
  done
  ar rcs libboost_program_options.a ./*.o
  # build.sh compares this with Homebrew's boost/version.hpp to detect a stale
  # library after a Homebrew Boost upgrade.
  echo "$bv" > BOOST_VERSION
)
echo "   built 3rdParty/boost_po/libboost_program_options.a ($TAG)"
[ "$boost_only" = 1 ] && exit 0

echo
echo "Dependencies ready.  Now build d4 and the demo counter:"
echo "    ./build.sh"
echo "    (cd demo/counter && make c -j)"
echo "    ./demo/counter/build/counter -i instancesTest/cnfs/cnf5.cnf"
