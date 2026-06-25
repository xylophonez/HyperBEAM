# Check Node Readiness

Use this recipe before running operator-sensitive or remote-data examples. It shows what this node is, which core device index it uses, and whether remote devices can be loaded.

## Commands

```bash
curl -sS "http://localhost:8734/~meta@1.0/info/address"
curl -sS "http://localhost:8734/~meta@1.0/info/preloaded-devices-index"
curl -sS "http://localhost:8734/~meta@1.0/info/load-remote-devices"
curl -sS "http://localhost:8734/~meta@1.0/info/trusted-device-signers"
curl -sS "http://localhost:8734/~meta@1.0/info/format~hyperbuddy@1.0" | grep -i -E 'trusted|remote|preloaded'
```

## Check Policy And Routes

```bash
curl -sS "http://localhost:8734/~meta@1.0/info/format~hyperbuddy@1.0" | grep -i -E 'route|gateway|hook|auth|pay|meter|trusted|cache'
```

## Machine-Readable View

```bash
curl -sS "http://localhost:8734/~meta@1.0/info/~json@1.0/serialize"
```

The node message is local state. It is the right place to check prerequisites for devices such as `~arweave@2.9`, `~bundler@1.0`, `~copycat@1.0`, `~cache@1.0`, payment devices, auth hooks, and remote device loading.
