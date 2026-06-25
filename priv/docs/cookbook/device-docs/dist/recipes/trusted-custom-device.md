# Trusted Custom Device

This recipe takes a Forge-built device from local development to a node trust policy.

## Build And Test Locally

```bash
cd /tmp/hb-device-docs-forge/echo_lens
rebar3 device package
rebar3 device verify
rebar3 device test
```

## Run A Local Node With The Device

```bash
cat > device-test-8799.json <<'JSON'
{
  "port": 8799
}
JSON

HB_CONFIG=device-test-8799.json rebar3 device local
```

In another shell:

```bash
curl -sS "http://localhost:8799/~echo-lens@1.0/echo?input=hello"
curl -sS "http://localhost:8799/~echo-lens@1.0/upper?input=hello"
```

Expected:

```text
hello
HELLO
```

## Publish

```bash
rebar3 device publish --key wallet.json
```

Keep the printed spec ID, implementation ID, and signer address.

## Check A Node's Trust Policy

```bash
curl -sS "http://localhost:8734/~meta@1.0/info/load-remote-devices"
curl -sS "http://localhost:8734/~meta@1.0/info/trusted-device-signers"
curl -sS "http://localhost:8734/~meta@1.0/info/format~hyperbuddy@1.0" | grep -i -E 'trusted|remote|preloaded'
```

Use a direct pin when the operator wants exactly one implementation. Use a trusted signer when the signer should be allowed to publish upgrades.
