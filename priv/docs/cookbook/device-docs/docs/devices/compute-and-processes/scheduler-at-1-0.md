# ~scheduler@1.0

The scheduling device for process assignments. It exposes schedule, slot, status, next, and info behavior.

## When To Use It

- Store process assignments.
- Read slots for process compute.
- Operate a scheduler service on a node.

## Action Keys

| Key | What it does |
|---|---|
| `info` | Return scheduler information. |
| `schedule` | GET or POST process assignments. |
| `slot` | Read a slot assignment. |
| `status` | Return scheduler/process status. |
| `next` | Return the next assignment/slot where supported. |

## Local Examples

### Read a process slot

```bash
HB="${HB:-http://localhost:8734}"
PROCESS_ID="co-MIhejkMR8v3-oIvW8m_u3YfV7zXoII0ja1wk-IOo"
curl -fsS "$HB/$PROCESS_ID~process@1.0/slot/current"
```

Expected output: `2`.

### Read schedule assignments

```bash
HB="${HB:-http://localhost:8734}"
PROCESS_ID="co-MIhejkMR8v3-oIvW8m_u3YfV7zXoII0ja1wk-IOo"
curl -fsS "$HB/$PROCESS_ID~process@1.0/schedule/assignments/0/body/type"
curl -fsS "$HB/$PROCESS_ID~process@1.0/schedule/assignments/1/body/action"
curl -fsS "$HB/$PROCESS_ID~process@1.0/schedule/assignments/2/body/action"
```

Expected: `Process`, `Eval`, and `Increment`.

### Inspect scheduler status

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS -H 'accept: application/json' "$HB/~scheduler@1.0/status"
```

Expected: node-wide scheduler status.

## Composition

- Use under `~process@1.0/schedule` and `~process@1.0/slot`.
- Use with `~cron@1.0` for scheduled self-calls.

## Trust And Operation

Scheduler output depends on hosted process state and assignment signatures.

## Source

- Root module: `dev_scheduler`
- Helper modules: `dev_scheduler_cache`, `dev_scheduler_formats`, `dev_scheduler_registry`, `dev_scheduler_server`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
