# d4v2 (macOS fork) — debugging notes

This is Henry Kautz's macOS fork of d4v2 (github.com/HenryKautz/d4v2): the
original plus guarded changes so it builds on Apple Silicon with Homebrew GCC
(`build.sh`; commits 7e224d9, a7d1a59, a8bb66f).  The compiler binary is
`demo/compiler/build/compiler`; FiFO (~/Programming/FiFO) runs it as `d4` on PATH.

## Wrong circuits and random crashes on large CNFs — FIXED 2026-10-16

**Symptoms** (found compiling SimpleGrid planning problems for FiFO,
~/Programming/CLARA/SimpleGrid): from 8x8 horizon 15 up (4,096 vars, circuits
of ~1 M nodes), d4 silently returned circuits whose projected count was too
high (exit 0), or crashed at random (bus error / segfault / trap).  Repeated
runs on the same CNF differed.  Smaller problems were fine.

**Cause: a heap overflow in the original d4v2 code** (not the macOS port),
`ListLit::setListLit` in `src/heuristics/branchingHeuristic/BranchingHeuristic.cpp`.
`ListLit` carves decision-literal lists out of 1024-literal pages and recycles
freed blocks by size.  When a page filled, the unused tail was filed under the
*requested* size instead of its real length; when the page was exactly full
the "tail" was the address one past its end, filed as a 1-literal block.  The
next 1-literal request (all the projected heuristics ever ask for) wrote one
`Lit` past the 4 KB page into the neighbouring heap block.  Pages only fill
once more than 1024 lists are alive, i.e. decision depth > 1024, hence large
problems only.  What got overwritten depended on heap layout (ASLR), hence the
run-to-run randomness:
- a `std::vector<Lit>` of a branch's unit literals → the first literal of an
  OR arc replaced by another literal → wrong count, exit 0;
- Glucose's clause memory → crash in `Solver::propagate` (lldb backtrace showed
  a clause literal of 0x80000000).

**How it was found:** two WRONG dumps of 8x8-3 had identical search
statistics and differed in only two lines, each in the first literal of a
long left OR branch.  A checksum of every node's literals at creation,
rechecked before printing, showed 0 nodes changed after creation, so the bad
data was already in the input vectors.  An ASan build (Homebrew g++-16
supports `-fsanitize=address` on this Mac) then reported the write 4 s in:
heap-buffer-overflow, 4 bytes, 0 bytes past a 4096-byte region, in
`setListLit`.

**Fix:** file the tail under its real length (none when the page is full).
Also from the code review: lists longer than a page get their own block (was
only an `assert`), copying a `ListLit` is a compile error, the destructor
skips empty lists.

**Verified:** with the fixed release binary, 8x8-2/3/4 OK 3/3 each, 9x9-1/2/3/4
OK (all previously crashed or were wrong); full ASan runs of 8x8-3 clean and
correct; a 1100-literal clause with `--branching-heuristic large-arity` clean
under ASan with the right count (2^1100 − 1).

Counts: grid8x8-2 7,856,368; -3 4,160,312; -4 8,536,710; grid9x9-1 16,913,390;
-2 17,737,109; -3 8,095,152; -4 10,575,175 (also in expected-counts.txt).

### Other fixes made at the same time

- `src/utils/MemoryStat.hpp`: read `/proc/self/stat`, which macOS lacks, and
  printed an uninitialized value as the `mem(MB)` column.  macOS branch now
  reports peak RSS via `getrusage`.  Cosmetic; not related to the bug.
- `src/caching/bucket/cnf/BucketManagerCnfCl.hpp`: off-by-one in the bitmap
  cache-key size (`1 + ((max-1)>>3)` bytes for bits 0..max).  Original d4v2
  code.  Did not cause the wrong counts (8x8-3 stayed wrong with it fixed).

### Ruled out along the way

Stack size (crashes at both 8 MB and 64 MB), the compiler toolchain, FiFO's
import, the input, NDEBUG-dependent class layouts, and integer overflow in the
cache headers/allocator at these sizes.

### Upstream

The `ListLit` bug and the bitmap off-by-one are in the original d4v2 code.
Reported upstream as https://github.com/crillab/d4v2/issues/14 (text in
`debug/upstream-issue.md`); it suggests replacing the hand-written pool with a
per-list `std::vector<Lit>` (the fragile part).  The same report notes that
upstream issue #3 no longer reproduces with current `main`.

`~/bin/d4` (what FiFO runs) was replaced with the fixed build on 2026-10-16.
`demo/compiler/build/compiler.orig` is the old buggy build, kept for
comparison.

## Building

- `./build.sh` (or `demo/compiler/build.sh`).  On macOS it first checks
  `3rdParty/boost_po/BOOST_VERSION` against Homebrew's Boost headers and
  rebuilds our g++ build of boost::program_options
  (`./setup-macos-deps.sh --boost-only`) when Homebrew has upgraded Boost —
  otherwise the demo link fails with missing `boost::program_options` symbols.
- The release build compiles libd4 with `-D NDEBUG` (asserts off).
- ASan build used for the hunt: `cmake -S . -B build-asan -G "Unix Makefiles"
  -DCMAKE_C_COMPILER=gcc-16 -DCMAKE_CXX_COMPILER=g++-16 -DBUILD_MODE=1
  "-DCMAKE_CXX_FLAGS=-fsanitize=address -fno-omit-frame-pointer"`, then compile
  the demo sources and Glucose's Solver/Options/System `.cc` with
  `-fsanitize=address -g -O2` and link them by hand with build-asan/libd4.a,
  flowCutter, patoh, bipe and boost_po (build.sh's library merge is not used).
  Output binary: `demo/compiler/build/compiler_asan`.
- ASan does not see overruns *inside* d4's own pools (cache pages, node
  pages); it caught this one only because a ListLit page is a separate `new[]`.

## Test kit: debug/simplegrid/

- `cnf/*.cnf` — the formerly failing inputs exactly as FiFO gave them to d4
  (with the `c p show` projection line): grid8x8-2/3/4, grid9x9-1/2/3/4.
- `expected-counts.txt` — the correct projected counts, from an independent
  dynamic program over truck walks.
- `count_nnf.py nnf CNF DUMP` — exact big-integer count of a d4 dump over the
  projected variables (needs the `c p show` line).
- `check.sh [-n RUNS] PROBLEM [d4 options...]` — runs d4 RUNS times and prints
  OK / WRONG / CRASH per run; keeps a failing run's dump and log under `work/`.
  `D4=...` selects a binary, `STACK=<KB>` the stack limit (default: hard max),
  `TAG=...` prefixes the work directories so runs can go in parallel.

Timing (fixed release binary, default options): 8x8 ~2–2.5 min; 9x9 5–10 min.
Two 9x9 runs at once can use several GB each (16 GB machine).  stdout is
block-buffered into the log, so a crash loses the last progress lines; use
lldb (`lldb --batch -o run -k "bt 40" -- compiler ...`) for a backtrace.
