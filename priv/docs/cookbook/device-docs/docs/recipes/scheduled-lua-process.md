# Inspect A Scheduled Lua Process Shape

This recipe shows the safe parts of a scheduled Lua workflow: a Lua module can run inline, and a process-shaped message can name Lua as its execution device. It does not register cron tasks or schedule messages.

## Run The Lua Handler

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS -X POST \
  -H 'content-type: application/json' \
  --data-binary '{"device":"lua@5.3a","content-type":"application/lua","body":"function tick(base, req, opts) return { body = \"tick:\" .. (req.Action or \"none\") } end"}' \
  "$HB/tick/body?Action=Tick"
```

Expected output: `tick:Tick`.

## Build The Assignment Shape

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/~message@1.0&device=process%401.0&execution-device=lua%405.3a&Action=Tick&Data=hello/~json@1.0/serialize"
```

Expected: JSON with `device`, `execution-device`, `Action`, and `Data`.

Cron and process scheduling require signing and operator-safe scheduling policy. Read-only process examples should use the seeded process fixture recipe.
