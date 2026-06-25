# ~cookie@1.0

A cookie commitment and authentication device. It can generate, finalize, commit, and verify cookie-backed authorization material.

## When To Use It

- Authenticate browser-style requests.
- Generate auth material through `~auth-hook@1.0`.
- Verify cookie commitments in a request pipeline.

## Action Keys

| Key | What it does |
|---|---|
| `generate` | Create a cookie challenge or auth value. |
| `finalize` | Finalize cookie auth flow. |
| `commit` | Commit cookie material. |
| `verify` | Verify cookie commitment. |
| `generator interface` | Participate as a generator behind auth-hook. |

## Local Examples

### Parse an incoming Cookie header

```bash
curl -sS -H 'accept: application/json' \
  "http://localhost:8734/~cookie@1.0/from?cookie=session%3Dabc123%3B%20theme%3Ddark"
```

Expected: a message whose private cookie map contains `session=abc123` and `theme=dark` in normalized form. This is how a hook turns browser cookie headers into structured authentication state.

### Emit a Set-Cookie header line

```bash
curl -sS -i -H 'accept: application/json' \
  "http://localhost:8734/~cookie@1.0/to?format=set-cookie&session=abc123&theme=dark"
```

Expected: a response message containing `set-cookie` lines. Use `format=cookie` to produce a single outbound `Cookie:` header instead.

### Generate then verify cookie-backed auth state

```bash
curl -sS -i "http://localhost:8734/~cookie@1.0/generate" | tee /tmp/hb-cookie-generate.txt
COOKIE=$(grep -i '^set-cookie:' /tmp/hb-cookie-generate.txt | sed 's/^[Ss]et-[Cc]ookie: //' | cut -d';' -f1 | paste -sd '; ' -)
curl -sS -i -H "Cookie: $COOKIE" "http://localhost:8734/~cookie@1.0/verify"
```

Expected: `generate` creates a secret-backed cookie when the node has a cookie provider configured; `verify` accepts the same cookie and rejects missing or altered cookies. On a node without the provider, the response will say which auth state is missing.

## Composition

- Use with `~auth-hook@1.0`, `~secret@1.0`, and browser clients.

## Trust And Operation

Cookies are bearer-like auth material. Treat them as secrets and scope them carefully.

## Source

- Root module: `dev_cookie`
- Helper modules: `dev_cookie_auth`, `dev_cookie_test_vectors`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
