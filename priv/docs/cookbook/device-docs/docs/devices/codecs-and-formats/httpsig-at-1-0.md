# ~httpsig@1.0

An HTTP Message Signatures commitment device based on RFC 9421-style signatures.

## When To Use It

- Commit HyperBEAM messages with HTTP signatures.
- Verify signed requests and responses.
- Produce portable HTTP signature headers and verify committed messages.

## Action Keys

| Key | What it does |
|---|---|
| `commit` | Create a signature commitment over a message. |
| `verify` | Verify an HTTP signature commitment. |
| `proxy-commit/proxy-verify` | Commit or verify when proxying signed messages. |
| `serialize/from/to` | Convert signature-bearing messages across representations. |

## Local Examples

### Return a HyperBEAM response as HTTP Message Signatures

```text
curl -sS -D /tmp/headers.txt "http://localhost:8734/~message@1.0&body=signed-response" -o /tmp/body.txt
sed -n '/^signature:/Ip;/^signature-input:/Ip;/^content-digest:/Ip' /tmp/headers.txt
cat /tmp/body.txt
```

Expected: the default response codec includes `signature`, `signature-input`, and `content-digest` headers. That is `httpsig@1.0` doing real work on the response.

### Commit a message with an HMAC secret

```bash
curl -sS -X POST \
  -H 'content-type: application/json' \
  --data-binary '{"body":"hello signed by secret","purpose":"demo"}' \
  "http://localhost:8734/~message@1.0/commit&commitment-device=httpsig@1.0&type=hmac-sha256&scheme=secret&secret=s3cr3t/~json@1.0/serialize"
```

Expected: the result has a `httpsig@1.0` HMAC commitment. Use `proxy-commit` when another auth device, such as `cookie@1.0` or `http-auth@1.0`, owns the secret.

### Commit and verify in one Hyperpath

```bash
curl -sS -X POST \
  -H 'content-type: application/json' \
  --data-binary '{"body":"hello signed by secret","purpose":"demo"}' \
  "http://localhost:8734/~message@1.0/commit&commitment-device=httpsig@1.0&type=hmac-sha256&scheme=secret&secret=s3cr3t/verify&commitment-device=httpsig@1.0&type=hmac-sha256&scheme=secret&secret=s3cr3t"
```

Expected: `true`. Keeping commit and verify in one path preserves the commitment material, including the HTTP signature fields.

## Composition

- Use with `~auth-hook@1.0`, `~secret@1.0`, `~cookie@1.0`, and Forge-published devices.

## Trust And Operation

Verification is meaningful only for the committed fields and signer you intend to trust.

## Source

- Root module: `dev_httpsig`
- Helper modules: `dev_httpsig_conv`, `dev_httpsig_keyid`, `dev_httpsig_proxy`, `dev_httpsig_siginfo`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
