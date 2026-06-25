# ~profile@1.0

A profiling device for measuring device execution. It can run profiling tools around an evaluation and return messages or console-oriented output.

## When To Use It

- Measure expensive device paths.
- Debug performance on a local node.
- Compare compute recipes under controlled inputs.

## Action Keys

| Key | What it does |
|---|---|
| `eval` | Evaluate a target request under the profiler. |
| `info` | Return profiling device information and supported options. |

## Local Examples

### Profile a cheap local resolution

```text
curl -sS "http://localhost:8734/~profile@1.0/eval?path=/~meta@1.0/info/address"
```

Expected: profiling output plus the target result, depending on configured profile engine/return mode.

### Return event profiling data

```text
PROFILE_NODE="<local-node-with-event-profiling>"
curl -sS "$PROFILE_NODE/~profile@1.0/eval?engine=event&path=/~message@1.0/body&body=hello"
```

Expected: event timing/counter information for the resolution.

### Profile a heavier query after copycat

```bash
curl -sS "http://localhost:8734/~profile@1.0/eval?path=/~query@1.0/all?return=count"
```

Expected: query result plus profiling metadata, useful when tuning cache/index behavior.

## Composition

- Use around Lua, WASM, query, and relay recipes while tuning them.

## Trust And Operation

Profiling can add overhead and exposes local execution details; use it on nodes you control.

## Source

- Root module: `dev_profile`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
