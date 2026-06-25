# Build A Process-Shaped Message

A process combines scheduler, execution, patching, and push behavior. This public recipe builds the message shape without scheduling or mutating process state.

## Serialize A Process Shape

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/~message@1.0&device=process%401.0&scheduler=scheduler%401.0&execution-device=lua%405.3a&push-device=push%401.0/~json@1.0/serialize"
```

Expected: JSON with `device`, `scheduler`, `execution-device`, and `push-device` fields.

## Inspect Scheduler Contract

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/~scheduler@1.0/info/schema"
```

Expected: a JSON schema object for scheduler actions.

## Inspect Push Contract

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/~push@1.0/info/schema"
```

Expected: a JSON schema object for push actions.

Scheduling, slot reads, and process compute examples must include a deterministic process fixture. A placeholder `PROCESS_ID` is not acceptable for inherited public recipes.
