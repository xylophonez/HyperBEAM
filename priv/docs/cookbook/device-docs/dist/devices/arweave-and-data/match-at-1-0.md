# ~match@1.0

A reverse index for finding message IDs that contain a specific key/value pair.

## When To Use It

- Look up cached messages by exact field values.
- Support `~query@1.0` matching under the hood.
- Debug local index coverage.

## Action Keys

| Key | What it does |
|---|---|
| `default key match` | A request key is treated as the key to match in the reverse index. |
| `all` | Intersect matches across all fields in the base message. |
| `info` | Expose default matching behavior and excluded keys. |

## Local Examples

Inspect workflow examples show request, configuration, or operator command shapes. Run them only after providing the stated local prerequisites; the browser runner does not execute these blocks.

### Confirm the match device is loaded

```text
curl -sSI "http://localhost:8734/~match@1.0/info" | grep -i -E 'status|default|excludes|content-type'
```

Expected: response headers showing `status: 200` plus the default match function and excluded keys. This proves the reverse-index device is loaded without depending on a specific cached key/value pair.

### Check whether the local query index has entries

```bash
curl -sS "http://localhost:8734/~query@1.0/all?return=count"
curl -sS "http://localhost:8734/~query@1.0/all?return=boolean"
```

Expected: a numeric count, then `true` or `false`. Query uses the same reverse-index idea as `~match@1.0`, but provides the easier application-facing surface.

### Query a single reverse-index key directly after indexing data

```text
http://localhost:8734/~match@1.0&KEY=VALUE
```

Expected after the node has indexed matching data: raw match-index entries for that exact key/value pair. Use direct `match` when debugging why a higher-level query did or did not find a cached message.

## Composition

- Use indirectly through `~query@1.0` for most applications.
- Use directly when debugging exact key/value index entries.

## Trust And Operation

Match results depend on the local match index. If the node has not indexed a message, match cannot find it.

## Source

- Root module: `dev_match`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
