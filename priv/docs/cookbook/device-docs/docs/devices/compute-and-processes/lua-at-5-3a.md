# ~lua@5.3a

The Lua execution device. It calls Lua modules on HyperBEAM messages and supports process lifecycle actions.

## When To Use It

- Run lightweight programmable transformations.
- Build AO process logic in Lua.
- Snapshot and normalize Lua-backed process state.

## Action Keys

| Key | What it does |
|---|---|
| `init` | Initialize Lua process state. |
| `compute` | Run Lua logic against a message. |
| `snapshot` | Return Lua state snapshot. |
| `normalize` | Prepare Lua state/message shape. |
| `functions` | Expose callable Lua functions when available. |

## Local Examples

### Run an inline Lua handler

```text
cat > /tmp/lua-process.json <<'JSON'
{
  "device": "lua@5.3a",
  "content-type": "application/lua",
  "body": "function handle(base, req, opts) return { body = 'hello ' .. (req.name or 'world') } end"
}
JSON
curl -sS -X POST -H 'content-type: application/json' --data-binary @/tmp/lua-process.json \
  "http://localhost:8734/handle/serialize~json@1.0?name=alice"
```

Expected: Lua state is initialized from the body and `handle` receives the path request as its second argument, returning a message with `body=hello alice`.

### Sandbox dangerous Lua functions

```text
cat > /tmp/lua-sandbox.json <<'JSON'
{
  "device": "lua@5.3a",
  "sandbox": true,
  "content-type": "application/lua",
  "body": "function handle(base, req, opts) return { ok = os == nil } end"
}
JSON
curl -sS -X POST -H 'content-type: application/json' --data-binary @/tmp/lua-sandbox.json \
  "http://localhost:8734/handle/serialize~json@1.0"
```

Expected: sandboxed globals such as `os` are absent or restricted.

### Use Lua inside a process definition

```text
cat > /tmp/lua-process-definition.json <<'JSON'
{
  "device": "process@1.0",
  "execution-device": "lua@5.3a",
  "scheduler-device": "scheduler@1.0",
  "body": "Handlers.add('Ping', function(msg) ao.send({Target = msg.From, Data = 'Pong'}) end)"
}
JSON
```

Expected: scheduled messages for this process are evaluated by `lua@5.3a`; state snapshots can later be read through `~process@1.0/now` or `compute`.

## Composition

- Use as the execution device under `~process@1.0`.
- Use with `~patch@1.0` to shape inputs and `~scheduler@1.0` to replay assignments.

## Trust And Operation

Lua output is only reproducible when the Lua module, state, assignment, and execution device are fixed and verifiable.

## Source

- Root module: `dev_lua`
- Helper modules: `dev_lua_lib`, `dev_lua_test`, `dev_lua_test_ledgers`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
