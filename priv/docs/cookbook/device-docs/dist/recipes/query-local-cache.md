# Inspect Query And Match Readiness

`~query@1.0` and `~match@1.0` depend on the local node's cache and reverse index. A recipe that checks for matches must first seed the index or it is not deterministic. The approved public recipe only inspects the match contract.

## Inspect The Match Contract

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/~match@1.0/info/schema"
```

Expected: a JSON schema object containing match actions such as `all`.

## Inspect The `all` Action

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/~match@1.0/info/schema/all"
```

Expected: JSON describing `/~match@1.0/all`.

Do not publish `return=count` or `return=boolean` as a canonical recipe unless the first step writes or imports a known fixture and the final step proves that fixture is the match. A node with an empty or different index can otherwise return 500, 0, or a true result for unrelated data.
