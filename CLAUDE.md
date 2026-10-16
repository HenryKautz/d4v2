# d4v2 (macOS fork) — debugging notes

This is Henry Kautz's macOS fork of d4v2 (github.com/HenryKautz/d4v2): the
original plus guarded changes so it builds on Apple Silicon with Homebrew GCC
(`build.sh`; commits 7e224d9, a7d1a59, a8bb66f).  The compiler binary is
`demo/compiler/build/compiler`; FiFO (~/Programming/FiFO) runs it as `d4` on PATH.

## The bug being chased (found 2026-10-16)

On larger CNFs, d4's compiler **silently returns wrong circuits** and **crashes
at random**.  It was found compiling SimpleGrid planning problems for FiFO's
plan-recognition experiments (~/Programming/CLARA/SimpleGrid).

- **Wrong circuits, exit 0:** the projected model count is too HIGH by 18 to 263
  (once 8x8-4 came out as 7,587 instead of 8,536,710; 8x8-3 once as 678).
  Repeated runs on the SAME CNF give different circuits, even different node
  counts.  With default options, 8x8-2 and 8x8-3 were wrong on nearly every
  run; 8x8-4 sometimes.
- **Crashes:** bus error, segmentation fault, or Trace/BPT trap, at random
  times, sometimes 0.3 s in, sometimes after minutes.  9x9-1/2/3 crashed on
  every run (6 each); 9x9-4 once finished (715 s, 2.19 M nodes).
- **Garbage in the progress output:** the `mem(MB)` column prints nonsense
  values, which suggests uninitialized or freed memory being read.
- **Scale:** nothing went wrong on 20 problems from 3x3 to 7x7 (up to 2,436
  vars / 17,936 clauses, circuits up to 109k nodes), nor on 8x8-1 (3,808 vars,
  341k nodes).  Failures start at 8x8 horizon 15: 4,096 vars, 30,753 clauses,
  circuits of 0.8–1.0 M nodes.
- **Options that helped but did not fix it:** `--cache-store-strategy all`
  (default is not-touched) and smaller cache pages,
  `--cache-size-first-page 268435456 --cache-size-additional-page 268435456`
  (default first page 4 GB), made wrong circuits rarer, not absent.  This hints
  at the cache (eviction/page handling).  `--partialOrder-heuristic none` and
  `--cache-clause-representation combi` made it worse.
- All runs used **projection** (a `c p show ... 0` line in the CNF) and
  `--dump-file`.  The projection itself is exact (FiFO checks definability), so
  every projected count must equal the expected count.

### Already ruled out

- **The compiler toolchain:** built with Homebrew g++-16 (not Apple clang), links
  Homebrew libstdc++ (`otool -L`).  (On this machine a clang-built C++ solver
  once segfaulted where g++ was fine, so this was checked first.)
- **FiFO's import of the dump:** the wrong counts come straight from d4's raw
  dump, counted by the independent `count_nnf.py` with no FiFO involved; and a
  known-good dump imported through FiFO counts exactly.
- **The input:** the same CNF gives correct and wrong circuits on different runs.

### Binaries

`~/bin/d4` (Aug 24) and `demo/compiler/build/compiler` (Jun 30) are the same
size but differ at byte 617 — probably a relink or re-signing of the same build;
origin of `~/bin/d4` not confirmed.  All the failures above were with `~/bin/d4`.
Check the build tree matches the source before trusting a rebuild.

## Test kit: debug/simplegrid/

- `cnf/*.cnf` — the failing inputs exactly as FiFO gave them to d4 (with the
  `c p show` projection line): grid8x8-2/3/4, grid9x9-1/2/3/4.
- `expected-counts.txt` — the correct projected counts, from an independent
  dynamic program over truck walks (it matched sharpSAT on all 20 problems from
  3x3 to 7x7; sharpSAT could not finish 8x8 in 2.5 h).
- `count_nnf.py nnf CNF DUMP` — exact big-integer count of a d4 dump over the
  projected variables (smooths each OR arc and the root itself).
- `check.sh [-n RUNS] PROBLEM [d4 options...]` — runs d4 RUNS times on a CNF and
  prints OK / WRONG / CRASH per run; keeps a failing run's dump and log under
  `work/`.  `D4=~/bin/d4 ./check.sh ...` selects a binary.  Not yet run end to
  end (its logic is that of the script that produced the results above).

Timing to expect per run (default options): 8x8-4 ~2 min, 8x8-3 ~3.5 min,
8x8-2 ~5 min; 9x9 either crashes early or runs 10+ minutes.  Use 8x8-2 or
8x8-3 to reproduce wrong circuits, 9x9-1/2/3 to reproduce crashes.  Two d4 runs
at once on 9x9 can use several GB each (16 GB machine).

## Suggested next steps

1. Rebuild from this source (`./build.sh`; `-d` sets a debug BUILD_MODE) and
   confirm the rebuilt binary still reproduces (check.sh -n 5 grid8x8-3).
2. Build with a memory checker.  Find out whether Homebrew GCC supports
   `-fsanitize=address` (and `-fsanitize=undefined`) on this Mac; if it does not,
   ask before falling back to Apple clang's sanitizers (the user's standing rule
   is Homebrew g++ unless they say otherwise).  Valgrind does not run on Apple
   Silicon.
3. Look at the cache code first (the options above change the failure rate),
   and at whatever prints the `mem(MB)` column.
4. Once fixed: every CNF in debug/simplegrid should give OK on repeated runs
   with default options; report upstream to the d4v2 authors if the bug is in
   the original code rather than the macOS changes.
