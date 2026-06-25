# Compute Over Arweave JSON With Lua

This recipe starts from a local node with no special application state, copies one Arweave block into the node, finds an `application/json` transaction, turns the Arweave-shaped result into JSON, and computes over that message with `~lua@5.3a`.

The example transaction is:

```bash
BLOCK=1936565
TXID=wKzEejXI5AlypYl82NYzgtBNIAOg10Ui0EWM4bkYRN4
```

That transaction is in block `1936565` and carries `content-type: application/json`.

## Copy The Block

```bash
curl -sS "http://localhost:8734/~copycat@1.0/arweave?from=$BLOCK&to=$BLOCK&mode=write"
```

Expected:

```text
1936565
```

List the transactions that copycat indexed from that block:

```bash
curl -sS "http://localhost:8734/~copycat@1.0/arweave?from=$BLOCK&to=$BLOCK&mode=list"
```

Expected: JSON with the copied block height and an `indexed` list. The list should include `wKzEejXI5AlypYl82NYzgtBNIAOg10Ui0EWM4bkYRN4`.

## Confirm The Transaction Is In The Copied Block

Ask copycat for the copied transaction list and filter for the example transaction:

```bash
curl -sS "http://localhost:8734/~copycat@1.0/arweave?from=$BLOCK&to=$BLOCK&mode=write" >/dev/null
curl -sS "http://localhost:8734/~copycat@1.0/arweave?from=$BLOCK&to=$BLOCK&mode=list" | grep "$TXID"
```

Expected: a line containing `wKzEejXI5AlypYl82NYzgtBNIAOg10Ui0EWM4bkYRN4`. This avoids depending on the optional GraphQL query path; copycat's Arweave block index is enough for this recipe.

## Confirm The JSON Transaction

Read the transaction header through `~arweave@2.9`:

```bash
curl -sS -i \
  "http://localhost:8734/~arweave@2.9/tx=$TXID?exclude-data=true" | \
  grep -i -E '^(appname|author|content-type|data_size|postslug|status):'
```

Expected: headers like these:

```text
appname: Paragraph
author: The White Rider
content-type: application/json
data_size: 23671
postslug: slit-we-were-the-regenerators-all-along
status: 200
```

You can also serialize that transaction message as JSON:

```bash
curl -sS \
  "http://localhost:8734/~arweave@2.9/tx=$TXID/serialize~json@1.0?exclude-data=true"
```

Expected: a JSON object containing transaction fields such as `appname`, `author`, `content-type`, `data_size`, `postslug`, and `commitments`.

## Parse The JSON Payload

On current edge nodes that have the transaction data bytes available, parse the transaction's JSON payload by targeting the transaction `data` field with `~json@1.0`:

```bash
curl -sS \
  "http://localhost:8734/~arweave@2.9/tx=$TXID/deserialize~json@1.0&target=data/serialize~json@1.0"
```

Expected: the JSON data payload decoded as a HyperBEAM message and serialized back to JSON for inspection. If the node has only indexed the transaction header so far, the command fails with a missing `data` target; the transaction header path above is still usable, and the Lua step below computes over that Arweave-derived JSON message.

## Compute Over The JSON Message With Lua

Turn the Arweave JSON message into a Lua device message by adding a small Lua module at the front of the object, then call `summarize`.

```bash
sed 's#^{#{"device":"lua@5.3a","module":{"content-type":"application/lua","body":"function summarize(base, req, opts) local n = 0; for k, v in pairs(base) do if k ~= \\"device\\" and k ~= \\"module\\" and k ~= \\"commitments\\" then n = n + 1 end end; return { body = (base.author or base.appname or \\"json\\") .. \\" / fields=\\" .. tostring(n) .. \\" / bytes=\\" .. tostring(base.data_size or \\"unknown\\"), content_type = base[\\"content-type\\"] or \\"application/json\\", tx = req.txid or \\"unknown\\" } end"},#' \
  /tmp/hb-arweave-json-tx.json > /tmp/hb-arweave-json-lua.json

curl -sS -X POST \
  -H 'content-type: application/json' \
  --data-binary @/tmp/hb-arweave-json-lua.json \
  "http://localhost:8734/summarize/serialize~json@1.0?txid=$TXID"
```

Expected:

```json
{"body":"The White Rider / fields=18 / bytes=23671","content_type":"application/json","tx":"wKzEejXI5AlypYl82NYzgtBNIAOg10Ui0EWM4bkYRN4"}
```

The Lua function walks the transaction message, counts public fields other than `device`, `module`, and `commitments`, chooses a human label from `author` or `appname`, carries forward the content type, and returns the transaction ID supplied in the request query. The exact `fields` count may differ by node version because transaction messages include node- and codec-specific commitment fields. The useful point is the composition: `~copycat@1.0` imports a block, `~arweave@2.9` materializes a transaction as a message, `~json@1.0` makes the result inspectable or parses a JSON payload, and `~lua@5.3a` computes a new message over that verifiable input.

## Swap In The Payload

If `/tmp/hb-arweave-json-payload.json` exists from the payload parse step, run the same Lua splice over that file instead:

```bash
sed 's#^{#{"device":"lua@5.3a","module":{"content-type":"application/lua","body":"function summarize(base, req, opts) local n = 0; for k, v in pairs(base) do if k ~= \\"device\\" and k ~= \\"module\\" and k ~= \\"commitments\\" then n = n + 1 end end; return { body = \\"payload fields=\\" .. tostring(n), tx = req.txid or \\"unknown\\" } end"},#' \
  /tmp/hb-arweave-json-payload.json > /tmp/hb-arweave-payload-lua.json

curl -sS -X POST \
  -H 'content-type: application/json' \
  --data-binary @/tmp/hb-arweave-payload-lua.json \
  "http://localhost:8734/summarize/serialize~json@1.0?txid=$TXID"
```

That version computes over the transaction's JSON payload instead of its transaction header message.
