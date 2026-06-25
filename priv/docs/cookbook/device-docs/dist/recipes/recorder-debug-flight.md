# Recorder Debug Flights

Recorder examples are operator-only until the docs-test node has a successful structured recorder fixture. The previous recipe returned HTTP 200 while the recorded target result was `not_found`, which is not acceptable for an inherited example.

An acceptable recorder recipe must:

- Install or confirm `~recorder@1.0` on the target node.
- Use a structured target request, not a string that silently loses query fields.
- Prove the recorded target result is successful.
- Redact private headers, wallets, cookies, and authorization material.
- Run on a private or disposable node when request contents are sensitive.

Until that fixture exists, use recorder in Forge/operator test suites rather than as a public runnable recipe.
