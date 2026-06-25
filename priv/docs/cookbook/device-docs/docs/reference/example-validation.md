# Example Validation

Use the strict recipe validator before publishing recipe changes:

```text
HB=https://docs-test.mystical.computer CURL_EXAMPLE_DOCS_DIR=docs/recipes CURL_EXAMPLE_FAIL_ON_SKIP=1 node scripts/validate-curl-examples.mjs
```

The strict pass must end with `0 failed` and `0 skipped`.

Run the broad docs validator before deploying generated device docs:

```text
HB=https://docs-test.mystical.computer node scripts/validate-curl-examples.mjs
```

The broad pass must also end with `0 failed` and `0 skipped`. If an example depends on operator configuration, local files, wallets, mutable cache state, signed fixtures, private routes, or an expected error response, keep it in a `text` fence rather than `bash`.

## Quick Curl Smoke Test

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/~message@1.0&greeting=hello/greeting"
curl -fsS "$HB/~message@1.0&count+integer=42/count"
curl -fsS "$HB/~message@1.0&greeting=hello/~json@1.0/serialize"
curl -fsS "$HB/~message@1.0&body=hello/~gzip@1.0/zip/~gzip@1.0/unzip/body"
PROCESS_ID="co-MIhejkMR8v3-oIvW8m_u3YfV7zXoII0ja1wk-IOo"
curl -fsS "$HB/$PROCESS_ID~process@1.0/compute/counter"
```

Expected: the first two commands return `hello` and `42`; the JSON command returns a serialized message; the gzip command returns `hello`; the process fixture command returns `1`.

Operator-sensitive and remote-data examples depend on node configuration. Do not treat a not-found, unauthorized, or unavailable response as a passing public recipe unless the recipe says that response is the expected result and the validator checks it.
