# ~blacklist@1.0

A request-hook device for content moderation. It refreshes provider data and blocks requests whose IDs match configured blacklist sources.

## When To Use It

- Block locally disallowed message IDs.
- Run moderation as a node preprocessor.
- Check blacklist provider configuration.

## Action Keys

| Key | What it does |
|---|---|
| `request hook` | Evaluate an incoming request and reject blacklisted IDs. |
| `blacklist-providers` | Node configuration listing provider sources. |
| `refresh/cache` | Maintain local blacklist cache state. |

## Local Examples

### Configure a newline blacklist provider

```bash
cat >/tmp/blacklist.txt <<'EOF'
BAD_MESSAGE_ID_1
BAD_MESSAGE_ID_2
EOF
python3 -m http.server 9911 --directory /tmp >/tmp/blacklist-http.log 2>&1 &
cat > /tmp/hb-blacklist.flat <<'EOF'
on/request/device: blacklist@1.0
blacklist-providers/1/path: http://localhost:9911/blacklist.txt
EOF
```

Expected: the hook refreshes the provider, parses newline-delimited IDs, and stores them in its local blacklist table.

### Run a request through blacklist policy

```bash
BLACKLIST_NODE="<node-with-blacklist-hook>"
curl -sS "$BLACKLIST_NODE/BAD_MESSAGE_ID_1/~message@1.0/id"
```

Expected: once initialized, a matching request is rejected before normal resolution. Non-matching requests continue.

### Use multiple providers

```bash
cat >> /tmp/hb-blacklist.flat <<'EOF'
blacklist-providers/2/body: OTHER_BAD_ID
EOF
```

Expected: providers are merged as a union; if any provider lists the ID, the hook blocks it.

## Composition

- Use as a `~meta@1.0` preprocessor with other policy devices such as rate limit or payment.

## Trust And Operation

Blacklist decisions are local operator policy and may depend on provider freshness.

## Source

- Root module: `dev_blacklist`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
