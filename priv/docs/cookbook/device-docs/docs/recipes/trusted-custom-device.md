# Trusted Custom Devices

Trusted custom device loading is an operator workflow. A complete recipe requires a packaged device, a signer, an implementation transaction, and an explicit node trust policy. Placeholder commands are not a substitute for those artifacts.

An acceptable public workflow must provide:

- The exact device source or package commit.
- A reproducible package and verify command run in CI.
- The spec transaction ID, implementation transaction ID, and signer address.
- The node policy that pins the implementation or trusts the signer.
- A read-only smoke path that proves the loaded device is the intended one.

Publish runnable commands only when those artifacts are available. Otherwise, keep custom device trust instructions in Forge/operator documentation and avoid commands that assume `/tmp` projects, local ports, wallet files, or unpublished transaction IDs.
