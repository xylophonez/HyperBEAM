# Scheduled Lua Process Pattern

This pattern shows the moving parts for a scheduled Lua-backed process. It is useful before you have a fully signed process fixture because it lets you verify the node has each device and see the shape each stage expects.

## Check Lua And Scheduler Devices

```bash
curl -sS "http://localhost:8734/~lua@5.3a/info/format~hyperbuddy@1.0"
curl -sS "http://localhost:8734/~scheduler@1.0/info/format~hyperbuddy@1.0"
curl -sS "http://localhost:8734/~cron@1.0/info/format~hyperbuddy@1.0"
```

## Build A Lua Assignment Message Shape

```bash
curl -sS "http://localhost:8734/~message@1.0&device=process%401.0&execution-device=lua%405.3a&Action=Tick&Data=hello/format~hyperbuddy@1.0"
```

## Schedule A Self-Call Shape

```bash
curl -sS "http://localhost:8734/~cron@1.0/once?cron-path=~process@1.0/compute&Action=Tick"
```

On a configured process node, the cron path becomes a scheduled compute call. On an unconfigured node, use the response to see which process or scheduler input is missing.

## Compute And Push Flow

```text
cron once/every -> process schedule -> scheduler slot -> lua compute -> push outputs
```

Use `~patch@1.0` when the scheduled message shape does not match the Lua function's expected keys.
