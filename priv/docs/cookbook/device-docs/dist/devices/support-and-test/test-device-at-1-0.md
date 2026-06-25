# ~test-device@1.0

A built-in test helper device used by HyperBEAM tests and examples. It is useful for confirming device loading and resolver behavior, not for application logic.

## When To Use It

- Confirm a preloaded device can resolve.
- Use in local tests for device composition.
- Exercise simple expected responses.

## Action Keys

| Key | What it does |
|---|---|
| `test keys` | Return predictable values used by HyperBEAM tests. |
| `info` | Expose test-device behavior when available. |

## Local Examples

Inspect workflow examples show request, configuration, or operator command shapes. Run them only after providing the stated local prerequisites; the browser runner does not execute these blocks.

### Use the deterministic index target

```bash
curl -sS "http://localhost:8734/~test-device@1.0/index?name=HyperBEAM"
```

Expected: `i like HyperBEAM!`. This is a simple deterministic target for resolver and hook tests.

### Inspect the helper paths

```text
curl -sS "http://localhost:8734/~test-device@1.0/info/~json@1.0/serialize"
```

Expected: a JSON message whose `body` links to a helper-path description including `info`, `compute`, `init`, `snapshot`, and `append`.

### Use it in a cron stop test

```text
TASK=$(curl -sS "http://localhost:8734/~cron@1.0/once?cron-path=/~test-device@1.0/delay")
curl -sS "http://localhost:8734/~cron@1.0/stop?task=$TASK"
```

Expected: the one-shot task is registered, then stopped before the delayed target finishes.

## Composition

- Use in local tests, not public APIs.

## Trust And Operation

This device is for test/support flows. Do not build public application features around it.

## Source

- Root module: `dev_test`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
