# ~trie@1.0

A radix trie device with implicit leaves. It is useful for path-indexed data and prefix lookup structures.

## When To Use It

- Store prefix-keyed maps and list keys.
- Build path indexes inside messages.
- Support devices that need efficient key lookup.

## Action Keys

| Key | What it does |
|---|---|
| `get` | Read a key from the trie. |
| `set` | Write a key into the trie. |
| `keys` | List trie keys. |

## Local Examples

Inspect workflow examples show request, configuration, or operator command shapes. Run them only after providing the stated local prerequisites; the browser runner does not execute these blocks.

### Set values in a committed trie

```text
curl -sS "http://localhost:8734/~trie@1.0/set&car+integer=31337&card+integer=90210/~json@1.0/serialize" | tee /tmp/trie.json
```

Expected: a trie message containing both keys. The radix trie shares prefixes, so `car` and `card` occupy a compact committed structure.

### Read a key from that trie

```text
TRIE_ID=$(curl -sS -X POST -H 'content-type: application/json' --data-binary @/tmp/trie.json \
  "http://localhost:8734/~message@1.0/id")
curl -sS "http://localhost:8734/$TRIE_ID/get?key=car"
curl -sS "http://localhost:8734/$TRIE_ID/card"
```

Expected: `get?key=car` and default lookup `/card` return the stored values once the trie message is addressable in cache.

### List committed trie keys

```text
curl -sS -X POST -H 'content-type: application/json' --data-binary @/tmp/trie.json \
  "http://localhost:8734/~trie@1.0/keys/~json@1.0/serialize"
```

Expected: the set of keys stored in the trie.

## Composition

- Use inside devices that maintain path indexes or manifests.
- Use with `~patch@1.0` when moving path-keyed state.

## Trust And Operation

A trie is just a data structure; trust depends on the message or cache entry that contains it.

## Source

- Root module: `dev_trie`
- Helper modules: `dev_trie_props`
- Device inventory: HyperBEAM edge commit `c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`
