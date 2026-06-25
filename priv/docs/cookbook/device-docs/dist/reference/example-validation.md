# Example Validation

Use the strict recipe validator before publishing recipe changes:

```text
HB=https://docs-test.mystical.computer CURL_EXAMPLE_DOCS_DIR=docs/recipes CURL_EXAMPLE_FAIL_ON_SKIP=1 node scripts/validate-curl-examples.mjs
```

The strict pass must end with `0 failed` and `0 skipped`.

## Quick Curl Smoke Test

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/~message@1.0&greeting=hello/greeting"
curl -fsS "$HB/~message@1.0&count+integer=42/count"
curl -fsS "$HB/~message@1.0&greeting=hello/~json@1.0/serialize"
curl -fsS "$HB/~message@1.0&body=hello/~gzip@1.0/zip/~gzip@1.0/unzip/body"
```

Expected: the first two commands return `hello` and `42`; the JSON command returns a serialized message; the gzip command returns `hello`.

Operator-sensitive and remote-data examples depend on node configuration. Do not treat a not-found, unauthorized, or unavailable response as a passing public recipe unless the recipe says that response is the expected result and the validator checks it.
