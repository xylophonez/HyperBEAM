# Patch Process State

`~patch@1.0` moves values between paths so later devices see the keys they expect. This is common before Lua/WASM compute and after compute before push.

## Start With A Message Shape

```bash
curl -sS "http://localhost:8734/~message@1.0&input=hello&target=body/format~hyperbuddy@1.0"
```

## Apply A Patch Shape

```bash
curl -sS -X POST -H 'content-type: application/json' \
  --data-binary '{"patch-from":"input","patch-to":"state","input":{"greeting":"hello"},"state":{}}' \
  "http://localhost:8734/~patch@1.0/all/~json@1.0/serialize"
```

Expected: `state/greeting` is populated from `input/greeting`. In process stacks, the same `patch-from` and `patch-to` instructions usually live in the process or stack definition.

## Stack Pattern

```text
message assignment -> patch input/body -> lua compute -> patch result/messages -> push
```

## Operator Check

```bash
curl -sS "http://localhost:8734/~meta@1.0/info/format~hyperbuddy@1.0" | grep -i -E 'patch|stack|process|compute'
```

Patch definitions should be treated like executable configuration. Review them before using the output of a signed process or a trusted remote device.
