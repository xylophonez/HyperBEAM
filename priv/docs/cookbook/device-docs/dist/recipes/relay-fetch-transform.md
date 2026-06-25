# Inspect Relay Contract And Route Policy

`~relay@1.0` makes HTTP calls through node-controlled route policy. Relay examples are easy to get wrong because a route can return a browser shell or a policy response while still using HTTP 200. The public recipe inspects the contract instead of relaying arbitrary URLs.

## Inspect Relay Schema

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/~relay@1.0/info/schema"
```

Expected: a JSON schema object with `call`, `cast`, and `request`.

## Inspect The `call` Action

```bash
HB="${HB:-http://localhost:8734}"
curl -fsS "$HB/~relay@1.0/info/schema/call"
```

Expected: JSON describing the `method`, `peer`, `relay-path`, and `target` parameters.

A relay recipe that fetches a URL must assert the content it expected, not only that the HTTP status was 200. Remote URL and route-policy examples belong in operator tests until they have a fixture.
