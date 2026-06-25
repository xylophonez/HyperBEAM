# ~secret@1.0

A node-hosted secret and wallet device. It can generate, import, export, list, sync, and commit with secrets stored on the node under access control.

## When To Use It

- Run trusted-node signing workflows.
- Manage node-local secrets for hooks and private services.
- Commit messages with a wallet kept on the node.

## Action Keys

| Key | What it does |
|---|---|
| `generate` | Create a new secret or wallet under access control. |
| `import` | Import a supplied secret. |
| `export` | Export a secret when access control allows it. |
| `list` | List known secrets without exposing private material. |
| `sync` | Synchronize secret state. |
| `commit` | Commit/sign a message using a node-hosted secret. |

## Local Examples

Inspect workflow examples show request, configuration, or operator command shapes. Run them only after providing the stated local prerequisites; the browser runner does not execute these blocks.

### List node-hosted secret references

```bash
curl -sS "http://localhost:8734/~secret@1.0/list/~json@1.0/serialize"
```

Expected: a JSON message containing secret references, not private key material. A default node usually has at least its operator wallet available as a node-hosted signing secret.

### Generate a node-hosted in-memory secret

```text
KEYID="$NEW_SECRET_KEYID"
curl -sS "http://localhost:8734/~secret@1.0/generate?persist=in-memory&keyid=$KEYID"
```

Expected on a node with a configured access-control provider: a key reference, not a public key dump. Later `commit`, `export`, or `sync` calls must pass the access-control check attached during generation. On an unconfigured node, configure the access-control device first instead of treating a 500 as useful output.

### Commit a message through a hosted secret

```text
KEYID="$AUTHORIZED_SECRET_KEYID"
curl -sS "http://localhost:8734/~message@1.0&body=operator-owned/commit~secret@1.0&keyid=$KEYID/~json@1.0/serialize"
```

Expected: a message with commitments created by the node-hosted secret if the caller's access-control credentials verify. On an unconfigured node, the error identifies the missing secret or access-control state.

### Export only after access control passes

```text
KEYID="$AUTHORIZED_SECRET_KEYID"
curl -sS "http://localhost:8734/~secret@1.0/export?keyids=$KEYID"
```

Expected: either the exported secret metadata for authorized callers or a rejection. Treat export as sensitive operator functionality; do it on a disposable local node first.

## Composition

- Use with `~auth-hook@1.0`, `~httpsig@1.0`, and `~cookie@1.0` on trusted nodes.

## Trust And Operation

Only use node-hosted secrets on nodes you control or intentionally trust. Never expose private keys, cookies, or tokens in logs or docs.

## Source

- Root module: `dev_secret`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
