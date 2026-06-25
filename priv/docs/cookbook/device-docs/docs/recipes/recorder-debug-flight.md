# Record A Debug Flight

`~recorder@1.0` captures device request flow for debugging. Run it on a disposable or private node because recordings can include request contents.

Recorder must be present in the node's preloaded store. If the node returns `device_not_loadable` or `device-name-not-resolvable`, use a local HyperBEAM build with `dev_recorder` included, or record through Forge tests instead.

```bash
curl -sS "http://localhost:8734/~meta@1.0/info/format~hyperbuddy@1.0" \
  | grep -i 'recorder' || true
```

## Try A Short Flight

```bash
curl -m 5 -sS "http://localhost:8734/~recorder@1.0/record?request=/~meta@1.0/info/address&format=text"
```

## Record A Target Request

```bash
curl -m 5 -sS "http://localhost:8734/~recorder@1.0/record?request=/~meta@1.0/info"
```

## Use During Forge Tests

From a Forge device project:

```bash
rebar3 device test --record=errors
```

Use recorder output to understand which message shape reached a device, which key ran, and where a composed path failed.
