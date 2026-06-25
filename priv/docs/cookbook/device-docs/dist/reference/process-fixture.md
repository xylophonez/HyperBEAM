# Process Fixture

The public process fixture for docs examples is:

```text
co-MIhejkMR8v3-oIvW8m_u3YfV7zXoII0ja1wk-IOo
```

It is a small counter process seeded for documentation tests. It exposes stable read keys through `process@1.0/compute`:

- `counter`: current counter value, currently `1`
- `status`: `ready`
- `name`: `hyperbeam-docs-counter-fixture`
- `version`: `2026-06-25.1`
- `lastupdate`: timestamp from the last increment message

Use it when an example must prove a real process read path:

```bash
HB="${HB:-http://localhost:8734}"
PROCESS_ID="co-MIhejkMR8v3-oIvW8m_u3YfV7zXoII0ja1wk-IOo"
curl -fsS "$HB/$PROCESS_ID~process@1.0/compute/counter"
```

Expected output: `1`.

The fixture is public, but any node used as `HB` must be able to resolve or route the process. docs-test wires that routing through operator configuration so examples do not publish the seeding node URL.
