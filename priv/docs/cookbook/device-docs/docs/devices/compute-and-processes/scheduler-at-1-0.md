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

### Schedule a message on a process

```bash
PROCESS_ID="<process-id>"
curl -sS -X POST "http://localhost:8734/$PROCESS_ID~scheduler@1.0/schedule" \
  -H 'action: Ping' \
  --data-binary 'hello scheduler'
```

Expected: an assignment or slot result for the process schedule. The request must be signed/admissible on production scheduler nodes.

### Read a slot

```bash
PROCESS_ID="<process-id>"
curl -sS "http://localhost:8734/$PROCESS_ID~scheduler@1.0/slot&slot+integer=1/~json@1.0/serialize"
```

Expected: the scheduled message at slot 1 if available.

### Ask for the next assignable slot

```bash
PROCESS_ID="<process-id>"
curl -sS "http://localhost:8734/$PROCESS_ID~scheduler@1.0/next"
```

Expected: the next slot number or scheduler status response.

### Check scheduler status for a process

```bash
PROCESS_ID="<process-id>"
curl -sS "http://localhost:8734/$PROCESS_ID~scheduler@1.0/status/~json@1.0/serialize"
```

Expected: scheduler state for that process: latest slot, assignment status, or an error describing missing scheduler state.

## Composition

- Use under `~process@1.0/schedule` and `~process@1.0/slot`.
- Use with `~cron@1.0` for scheduled self-calls.

## Trust And Operation

Scheduler output depends on hosted process state and assignment signatures.

## Source

- Root module: `dev_scheduler`
- Helper modules: `dev_scheduler_cache`, `dev_scheduler_formats`, `dev_scheduler_registry`, `dev_scheduler_server`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
