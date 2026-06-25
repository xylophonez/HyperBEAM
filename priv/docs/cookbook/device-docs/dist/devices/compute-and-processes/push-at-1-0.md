# ~push@1.0

A process-output propagation device. It evaluates messages or slots and recursively pushes output messages to other processes.

## When To Use It

- Forward process outputs to recipient processes.
- Build multi-process workflows.
- Automate recursive message dispatch after compute.

## Action Keys

| Key | What it does |
|---|---|
| `push` | Evaluate and push output messages. |
| `slot/message inputs` | Read slot or message context from the base/request pair. |
| `recursive dispatch` | Continue pushing produced messages according to process output shape. |

## Local Examples

### Inspect a seeded process result before pushing

```bash
HB="${HB:-http://localhost:8734}"
PROCESS_ID="co-MIhejkMR8v3-oIvW8m_u3YfV7zXoII0ja1wk-IOo"
curl -fsS "$HB/$PROCESS_ID~process@1.0/compute/counter"
```

Expected: a real process state value. Actual push calls are side-effecting and must be signed/admissible on production scheduler nodes.

### Push one explicit message

```text
curl -sS -X POST -H 'content-type: application/json' \
  --data-binary '{"target":"<recipient-process>","data":"hello"}' \
  "http://localhost:8734/~push@1.0/one/~json@1.0/serialize"
```

Expected: the device wraps the target message into an assignment/push result when process context is configured.

### Pair with scheduler for delivery

```text
RECIPIENT="recipient process id"
curl -sS -X POST "http://localhost:8734/$RECIPIENT~scheduler@1.0/schedule" \
  -H 'action: Receive' \
  --data-binary 'hello from push workflow'
```

Expected: push ultimately feeds scheduler-compatible assignments for recipient processes.

## Composition

- Use through `~process@1.0/push` after compute.
- Use with `~scheduler@1.0` and `~stack@1.0` for process graphs.

## Trust And Operation

Pushed outputs should be verified against process and scheduler commitments.

## Source

- Root module: `dev_push`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
