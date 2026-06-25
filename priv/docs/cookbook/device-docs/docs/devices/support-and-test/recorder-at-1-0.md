# ~recorder@1.0

A debugging recorder that captures request/response flights for replay and diagnosis.

## When To Use It

- Debug device paths on a disposable node.
- Capture failing Forge tests with `--record`.
- Record multi-device request flow.

## Action Keys

| Key | What it does |
|---|---|
| `take-off` | Start a recording flight. |
| `land` | Finish a recording flight. |
| `record` | Record a target request. |
| `HTML archive output` | Produce human-readable debug artifacts when configured. |

## Availability Check

Recorder is a support/debug device. Some operator builds do not preload it. Check your node before using the examples:

```text
curl -sS "http://localhost:8734/~meta@1.0/info/format~hyperbuddy@1.0" \
  | grep -i 'recorder' || true
```

If `~recorder@1.0` returns `device_not_loadable` or `device-name-not-resolvable`, run a local HyperBEAM build whose preloaded store includes `dev_recorder`, or use Forge test recording from a device project.

## Local Examples

Inspect workflow examples show request, configuration, or operator command shapes. Run them only after providing the stated local prerequisites; the browser runner does not execute these blocks.

### Record one target request

```text
curl -sS "http://localhost:8734/~recorder@1.0/record?request=/~meta@1.0/info/address&format=text"
```

Expected: a text flight log showing the request, device calls, and response path for the target resolution.

### Take off, run a path, then land

```text
RECORDER_NODE="<local-node-with-recorder>"
curl -sS "$RECORDER_NODE/~recorder@1.0/take-off/~message@1.0&body=hello/body/land~recorder@1.0?format=text"
```

Expected: recorder captures the intermediate flight while the path runs, then `land` returns the captured report.

### Return JSON for tooling

```text
curl -sS "http://localhost:8734/~recorder@1.0/record?request=/~query@1.0/all%3Freturn%3Dcount&format=json"
```

Expected: structured recorder events that can be filtered in scripts.

## Composition

- Use with Forge `rebar3 device test --record=errors`.
- Use with operator devices only on disposable nodes because recordings can contain sensitive data.

## Trust And Operation

Recorder output may include request contents. Do not record secrets or credentials on shared nodes.

## Source

- Root module: `dev_recorder`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
