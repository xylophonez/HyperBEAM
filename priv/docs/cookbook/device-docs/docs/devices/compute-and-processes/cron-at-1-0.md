# ~cron@1.0

A scheduled self-call device. It inserts recurring or one-shot messages into an evaluation stream.

## When To Use It

- Schedule recurring process messages.
- Trigger maintenance paths such as copycat indexing.
- Stop or check scheduled jobs.

## Action Keys

| Key | What it does |
|---|---|
| `every` | Schedule a repeating call. |
| `once` | Schedule a single call. |
| `stop` | Stop a scheduled call. |
| `info` | Return schedule information. |

## Local Examples

Inspect workflow examples show request, configuration, or operator command shapes. Run them only after providing the stated local prerequisites; the browser runner does not execute these blocks.

### Schedule a recurring request with `every`

```bash
curl -sS "http://localhost:8734/~cron@1.0/every?interval=5-seconds&cron-path=/~meta@1.0/info/address"
```

Expected: a task ID. The cron worker resolves `/~meta@1.0/info/address` every five seconds until stopped. Use a harmless path first; on a process node the path is usually a process `compute` or `schedule` call.

### Stop the recurring task

```text
TASK_ID="<task-id-from-every>"
curl -sS "http://localhost:8734/~cron@1.0/stop?task=$TASK_ID"
```

Expected: a success message for a live task or `Task not found` if it already exited or the ID is wrong.

### Run a one-shot request

```bash
curl -sS "http://localhost:8734/~cron@1.0/once?cron-path=/~meta@1.0/info/address"
```

Expected: a task ID for a spawned one-shot worker. The worker resolves the target path once in the background.

## Composition

- Use with `~copycat@1.0` for recurring indexing.
- Use with `~process@1.0` and `~scheduler@1.0` for process time.

## Trust And Operation

Cron mutates evaluation flow. Run schedule changes only in processes or nodes you control.

## Source

- Root module: `dev_cron`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
