# ~rate-limit@1.0

A request-hook rate limiter keyed by client IP. It can reject excessive requests with HTTP 429 responses.

## When To Use It

- Protect a public node from bursts.
- Apply lightweight local policy before expensive device work.
- Expose operator-tunable request windows.

## Action Keys

| Key | What it does |
|---|---|
| `request hook` | Count requests and reject callers over the configured threshold. |
| `rate_limit_requests` | Allowed requests per period. |
| `rate_limit_period` | Window size. |
| `rate_limit_exempt` | Exempt clients or addresses. |

## Local Examples

Inspect workflow examples show request, configuration, or operator command shapes. Run them only after providing the stated local prerequisites; the browser runner does not execute these blocks.

### Configure a request-rate hook

```text
cat > /tmp/hb-rate-limit.flat <<'EOF'
on/request/device: rate-limit@1.0
rate-limit/window: 60-second
rate-limit/limit: 30
rate-limit/key: committer
EOF
```

Expected: the hook counts requests per committer for a 60-second window and rejects callers over 30 requests.

### Exercise the limit with repeated cheap requests

```text
for i in $(seq 1 35); do
  curl -sS -o /tmp/rate-$i.txt -w "%{http_code}\n" \
    "http://localhost:8734/~meta@1.0/info/address"
done
```

Expected: normal responses until the configured threshold is exceeded, then a rate-limit error.

### Change the keying strategy for shared clients

```text
cat >> /tmp/hb-rate-limit.flat <<'EOF'
rate-limit/key: ip
EOF
```

Expected: rate limiting by IP instead of committer. This is useful before auth hooks have signed the request.

## Composition

- Use before payment, relay, copycat, and compute-heavy devices.

## Trust And Operation

Counters are local and policy-specific. A 429 means this node rejected the request.

## Source

- Root module: `dev_rate_limit`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
