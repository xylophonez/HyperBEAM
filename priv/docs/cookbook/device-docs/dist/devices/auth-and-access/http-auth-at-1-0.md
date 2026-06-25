# ~http-auth@1.0

An HTTP Basic authentication device with PBKDF2 password handling and HMAC commitment support through HTTP signatures.

## When To Use It

- Protect node routes with browser-compatible auth prompts.
- Generate 401 challenges for clients.
- Commit authenticated requests with HTTP signature machinery.

## Action Keys

| Key | What it does |
|---|---|
| `generate` | Generate auth challenge/response behavior; can return 401 for browsers. |
| `commit/verify path` | Use HMAC/httpsig commitment behavior for authenticated requests. |
| `generator interface` | Participate behind `~auth-hook@1.0`. |

## Local Examples

### Trigger the Basic-auth challenge

```text
curl -sS -i "http://localhost:8734/~http-auth@1.0/generate"
```

Expected: `401 Unauthorized` with `www-authenticate: Basic` and details saying no Authorization header was provided. This is the browser challenge path.

### Derive raw auth material from a Basic header

```text
AUTH=$(printf 'alice:correct-horse' | base64 | tr -d '\n')
curl -sS -H "Authorization: Basic $AUTH" \
  "http://localhost:8734/~http-auth@1.0/generate?raw+atom=true"
```

Expected: `alice:correct-horse`. `raw=true` is for debugging only; normal auth-hook usage derives a PBKDF2 key instead of returning credentials.

### Derive a reproducible secret for signing

```text
AUTH=$(printf 'alice:correct-horse' | base64 | tr -d '\n')
curl -sS -H "Authorization: Basic $AUTH" \
  "http://localhost:8734/~http-auth@1.0/generate?iterations+integer=1200000&key-length+integer=64"
```

Expected: a deterministic encoded secret derived from the Basic credentials, salt, iteration count, and key length. `~auth-hook@1.0` passes that secret to `~secret@1.0`/`~httpsig@1.0` for request commitments.

### Commit and verify with the same Basic credential

```text
AUTH=$(printf 'alice:correct-horse' | base64 | tr -d '\n')
curl -sS -H "Authorization: Basic $AUTH" \
  "http://localhost:8734/~message@1.0&body=paywalled/commit~http-auth@1.0/~json@1.0/serialize" > /tmp/http-auth-committed.json
curl -sS -X POST -H "Authorization: Basic $AUTH" -H 'content-type: application/json' \
  --data-binary @/tmp/http-auth-committed.json \
  "http://localhost:8734/~http-auth@1.0/verify"
```

Expected: verification succeeds when the same Authorization header derives the same secret. Change the password and verification should fail.

## Composition

- Use with `~auth-hook@1.0`, `~httpsig@1.0`, and route policy.

## Trust And Operation

Password and HMAC configuration is sensitive. Test on a disposable node before exposing public routes.

## Source

- Root module: `dev_http_auth`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
