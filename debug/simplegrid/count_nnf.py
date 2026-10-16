#!/usr/bin/env python3
"""Exact (big-integer) model counts over the projected variables, independent of FiFO:
  count_circuits.py dnnf <file.dnnf>             FiFO's saved, smoothed circuit
  count_circuits.py nnf <d4-input.cnf> <dump.nnf>...  d4 dumps, smoothed here"""
import re, sys


def count_dnnf(path):
    text = open(path).read()
    root = int(re.search(r":ROOT (\d+)", text).group(1))
    start = text.index(":NODES (") + len(":NODES (")
    end = text.index(" :ATOMS")
    nodes = re.findall(r"\(:([FTLAO])([^()]*)\)", text[start:end])
    val = []
    for kind, args in nodes:          # children always precede parents (builder order)
        kids = [int(x) for x in args.split()]
        if kind == "F": val.append(0)
        elif kind in "TL": val.append(1)
        elif kind == "A":
            p = 1
            for k in kids: p *= val[k]
            val.append(p)
        else:
            val.append(sum(val[k] for k in kids))
    return val[root], len(nodes)


def count_nnf(cnf, path):
    proj = None
    for line in open(cnf):
        if line.startswith("c p show"):
            proj = [int(x) for x in line.split()[3:-1]]
            break
    ntype, arcs = {}, {}
    for line in open(path):
        f = line.split()
        if not f: continue
        if f[0].isalpha():
            ntype[int(f[1])] = f[0]
        else:
            arcs.setdefault(int(f[0]), []).append((int(f[1]), [int(x) for x in f[2:-1]]))
    dsts = {d for lst in arcs.values() for d, _ in lst}
    (root,) = [n for n in ntype if n not in dsts]
    scope, cnt = {}, {}
    stack, expanded = [(root, False)], set()
    while stack:
        n, done = stack.pop()
        if done:
            t = ntype[n]
            if t in "tf":
                scope[n], cnt[n] = 0, (1 if t == "t" else 0)
                continue
            s = 0
            parts = []
            for d, lits in arcs.get(n, []):
                m = scope[d]
                for l in lits: m |= 1 << abs(l)
                parts.append((d, m))
                s |= m
            if t == "a":
                c = 1
                for d, _ in parts: c *= cnt[d]
            else:  # 'o': smooth each arc up to the OR's scope
                c = sum(cnt[d] << (bin(s).count("1") - bin(m).count("1")) for d, m in parts)
            scope[n], cnt[n] = s, c
            continue
        if n in expanded: continue
        expanded.add(n)
        stack.append((n, True))
        for d, _ in arcs.get(n, []):
            if d not in expanded: stack.append((d, False))
    free = len(proj) - bin(scope[root]).count("1")
    return cnt[root] << free, len(ntype)


if __name__ == "__main__":
    if sys.argv[1] == "dnnf":
        c, n = count_dnnf(sys.argv[2])
        print(f"{sys.argv[2]}: {n} nodes, count {c}")
    else:
        for p in sys.argv[3:]:
            c, n = count_nnf(sys.argv[2], p)
            print(f"{p}: {n} nodes, count {c}")
