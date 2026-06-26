# Recorder Debug Flights

Recorder debug flights require a node with `~recorder@1.0`, a structured target request, and a successful recorded target result. A plain HTTP 200 is not enough when the captured target response is `not_found`.

An acceptable recorder recipe must:

- Install or confirm `~recorder@1.0` on the target node.
- Use a structured target request, not a string that silently loses query fields.
- Prove the recorded target result is successful.
- Redact private headers, wallets, cookies, and authorization material.
- Run on a private or disposable node when request contents are sensitive.

Until a successful recorder fixture is available, recorder examples belong in Forge or operator test suites rather than the public runnable recipe set.
