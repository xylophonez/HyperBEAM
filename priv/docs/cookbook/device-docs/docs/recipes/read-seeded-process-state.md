# Read Seeded Process State

This recipe reads a public counter process fixture. It proves the process read path with a real process ID instead of a placeholder.

The fixture currently exposes `counter`, `status`, `name`, `version`, and `lastupdate` through `process@1.0/compute`.

## Read The Counter

```bash
HB="${HB:-http://localhost:8734}"
PROCESS_ID="co-MIhejkMR8v3-oIvW8m_u3YfV7zXoII0ja1wk-IOo"
curl -fsS "$HB/$PROCESS_ID~process@1.0/compute/counter"
```

Expected output: `1`.

## Read Fixture Metadata

```bash
HB="${HB:-http://localhost:8734}"
PROCESS_ID="co-MIhejkMR8v3-oIvW8m_u3YfV7zXoII0ja1wk-IOo"
curl -fsS "$HB/$PROCESS_ID~process@1.0/compute/status"
curl -fsS "$HB/$PROCESS_ID~process@1.0/compute/name"
curl -fsS "$HB/$PROCESS_ID~process@1.0/compute/version"
```

Expected: `ready`, `hyperbeam-docs-counter-fixture`, and `2026-06-25.1`.

This recipe depends on the node being able to resolve the public fixture process. docs-test routes that fixture at the operator level.
