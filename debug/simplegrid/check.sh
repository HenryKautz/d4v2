#!/bin/bash
# check.sh [-n RUNS] PROBLEM [d4 options...]
#
# Compile cnf/PROBLEM.cnf with d4 RUNS times (default 1) and check each circuit's
# projected model count against expected-counts.txt, with count_nnf.py (an
# independent counter: it smooths d4's dump itself and counts with big integers).
# Prints one line per run: OK, WRONG (count and expected), or CRASH (exit code).
#
# D4 selects the binary (default: this checkout's demo/compiler/build/compiler).
# Work files go in work/PROBLEM-N/; a failing run's dump and d4 log are kept there.
#
#   ./check.sh grid8x8-2
#   ./check.sh -n 10 grid8x8-3 --cache-store-strategy all
#   D4=~/bin/d4 ./check.sh grid9x9-1
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
D4="${D4:-$HERE/../../demo/compiler/build/compiler}"
runs=1
if [ "${1:-}" = "-n" ]; then runs="$2"; shift 2; fi
prob="${1:?usage: check.sh [-n RUNS] PROBLEM [d4 options...]}"; shift
cnf="$HERE/cnf/$prob.cnf"
want="$(awk -v p="$prob" '$1 == p {print $2}' "$HERE/expected-counts.txt")"
[ -f "$cnf" ] || { echo "no $cnf" >&2; exit 2; }
[ -n "$want" ] || { echo "no expected count for $prob" >&2; exit 2; }
ulimit -s hard            # d4 recurses deeply; the default 8 MB stack is too small
for i in $(seq 1 "$runs"); do
  w="$HERE/work/$prob-$i"; rm -rf "$w"; mkdir -p "$w"
  start=$(date +%s)
  "$D4" -i "$cnf" --dump-file "$w/out.nnf" "$@" > "$w/d4.log" 2>&1
  rc=$?
  secs=$(( $(date +%s) - start ))
  if [ $rc -ne 0 ] || [ ! -s "$w/out.nnf" ]; then
    echo "$prob run $i: CRASH exit $rc after ${secs}s (log: $w/d4.log)"
    continue
  fi
  got="$(python3 "$HERE/count_nnf.py" nnf "$cnf" "$w/out.nnf" | sed 's/.*count //')"
  if [ "$got" = "$want" ]; then
    echo "$prob run $i: OK ${secs}s count $got"
    rm -rf "$w"
  else
    echo "$prob run $i: WRONG ${secs}s count $got, expected $want (dump: $w/out.nnf)"
  fi
done
