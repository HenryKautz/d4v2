# Heap overflow in ListLit::setListLit gives wrong d-DNNF circuits and random crashes on large instances

## Summary

On larger instances the compiler (`demo/compiler`, `ddnnf-compiler`) silently
produces **wrong circuits** (model count too high, exit status 0) or **crashes
at random** (SIGSEGV / SIGBUS), and repeated runs on the same CNF give
different results.  The cause is a one-element heap-buffer overflow in
`ListLit::setListLit` (`src/heuristics/branchingHeuristic/BranchingHeuristic.cpp`),
present in the current `main` (15eff31).

## The bug

`ListLit` carves decision-literal lists out of shared pages of
`SIZE_PAGE_LIST_LIT` (1024) literals and recycles freed blocks in
`s_availaible[size]`.  When a request does not fit in the current page, the
unused tail of that page is recycled before a new page is started:

```cpp
if (!s_currentPage || s_posPage + size > SIZE_PAGE_LIST_LIT) {
  if (s_currentPage) {
    while (s_availaible.size() <= size)
      s_availaible.push_back(std::vector<Lit *>());
    s_availaible[size].push_back(&s_currentPage[s_posPage]);   // <-- bug
  }
  ...
```

The tail is filed under `size`, the length of the request that did **not**
fit, rather than under its real length `SIZE_PAGE_LIST_LIT - s_posPage`, which
is smaller.  A later request for `size` literals gets the tail back and
writes past the end of the page.

In the common case, which is projected compilation where the heuristics only
ever ask for 1-literal lists, this happens when a page is exactly full
(`s_posPage == 1024`).  The "tail" is then the address one past the end of the
page, filed as a free 1-literal block, and the next request writes one `Lit`
past the 4 KB allocation.  A page fills only when more than 1024 lists are alive
at once, i.e. decision depth above 1024, so small instances are unaffected.

What gets overwritten depends on heap layout (ASLR), which is why runs differ.
We observed both outcomes:

- A branch's `std::vector<Lit>` of unit literals gets its first element
  replaced by another literal before the circuit node is built.  The dumped
  d-DNNF then has a wrong literal on an arc, and the count is too high.  Two
  wrong dumps of the same instance had identical search statistics and
  differed only in the first literal of one long OR branch each.
- Glucose's clause memory is corrupted, and the solver crashes in
  `Solver::propagate` on a clause literal of `0x80000000`.

## Evidence

AddressSanitizer build (g++ 16, `-fsanitize=address`), 4 s into compiling a
4,096-variable / 30,753-clause projected instance:

```
ERROR: AddressSanitizer: heap-buffer-overflow ...
WRITE of size 4 ...
    #0 d4::ListLit::setListLit(d4::Lit const*, int)
    #1 d4::BranchingHeuristicClassic::selectLitSet(std::vector<int>&, d4::ListLit&)
    #2 d4::DpllStyleMethod<...>::computeDecisionNode(...)
    ...
0x... is located 0 bytes after 4096-byte region
allocated by thread T0 here:
    #0 operator new[]
    #1 d4::ListLit::setListLit(d4::Lit const*, int)
```

With the fix below, the same instance runs to completion under ASan with no
errors.  Seven instances that previously failed now all give the correct
projected count, checked against an independent counter, on every run.  They
have 4,096 and 5,616 variables and 30,753 and 42,712 clauses, with circuits of
0.77 to 2.2 M nodes; before the fix they were wrong on most runs or crashed on
every run.  We can provide the CNF files.

## Fix

File the tail under its real length, and none at all when the page is full:

```cpp
if (!s_currentPage || s_posPage + size > SIZE_PAGE_LIST_LIT) {
  unsigned rest = s_currentPage ? SIZE_PAGE_LIST_LIT - s_posPage : 0;
  if (rest) {
    while (s_availaible.size() <= rest)
      s_availaible.push_back(std::vector<Lit *>());
    s_availaible[rest].push_back(&s_currentPage[s_posPage]);
  }
  ...
```

Related hardening we applied at the same time:

- **Lists longer than a page.** `size > SIZE_PAGE_LIST_LIT` is guarded only by
  an `assert`, so release builds overflow the new page.  This is reachable with
  `--branching-heuristic large-arity` and a clause of more than 1024 literals.
  We now give such a list its own `new Lit[size]` block.
- **Copies.** `ListLit` returns its block to the pool in its destructor but
  keeps the default copy operations, so a copy would return the same block
  twice.  We now `= delete` them.
- **Empty lists.** The destructor pushes `NULL` into `s_availaible[0]` for every
  empty list, which is never popped.  It now skips them.

Longer term, the hand-written pool is the fragile part; a per-list
`std::vector<Lit>` (or inline storage for one literal) would remove this class
of bug.  The fixes are in commit
https://github.com/HenryKautz/d4v2/commit/c11210d.

## Second, minor bug: bitmap cache key one byte short

`BucketManagerCnfCl::computeNeededBytes`
(`src/caching/bucket/cnf/BucketManagerCnfCl.hpp`) sizes the bitmap encoding
of a component's variables as `1 + ((component.back() - 1) >> 3)` bytes.
However, `storeVariables` sets bit `v` at byte `v >> 3`, which needs
`1 + (component.back() >> 3)` bytes.  When the largest variable is a multiple
of 8, the write lands one byte past the variable area: in the clause area,
where it is then wiped (so that variable drops out of the cache key), or past
the allocation when the component has no clauses.  This did **not** cause the
wrong counts above, but it is an out-of-bounds write.  The fix is to use
`1 + (component.back() >> 3)`.

## Also

Issue #3 (variable numbers truncated in the dump for 128–254 variables)
no longer reproduces with current `main`: its example now dumps `1 2 129 0`.
