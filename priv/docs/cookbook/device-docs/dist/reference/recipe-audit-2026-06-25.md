# Recipe Audit 2026-06-25

## Scope

This audit covers the docs-test on-weave `Device-Recipe` corpus and the static recipe pages shipped with the cookbook docs.

- On-weave corpus: 102 recipes across 32 devices.
- Operator quarantine: all 102 legacy on-weave recipes are listed in `config/docs-test-recipe-blacklist.json`.
- Replacement pack: the static cookbook recipe pages were rewritten into tested public recipes plus operator-only guidance.
- Strict validation target: `HB=https://docs-test.mystical.computer`, recipe directory only, fail on skipped examples.

## What Changed

| Area | Change | Why |
|---|---|---|
| Runtime docs | Added file-backed recipe blacklist support in `hb_docs`. | Operators need to hide known bad on-weave recipes without deleting or republishing transactions. |
| docs-test config | Added `config/docs-test-recipe-blacklist.json` and wired it from `scripts/hyperbeam-docs-test-start`. | The current public on-weave recipe corpus should not be inherited while it contains broken patterns. |
| Static recipes | Replaced local-file, placeholder, and operator-mutation examples with deterministic curl-only recipes. | Public recipes must be runnable from a fresh shell and pass on docs-test. |
| Process fixture | Added a seeded public counter process and `recipes/read-seeded-process-state.md`. | Process examples need a real process ID rather than inherited `PROCESS_ID` placeholders. |
| Validator | Added `HB` override, strict recipe-directory mode, skipped-example failure mode, and bad semantic output detection. | A 200 response is not enough when the body is an error page, Hyperbuddy shell, or failed recorder report. |
| Standards | Added `reference/recipe-standards.md`. | Future recipes need a stable acceptance bar before being published on weave. |

## Blacklisted Patterns

The quarantined on-weave corpus contains these non-exclusive bad patterns:

- Local files or shell history, especially `/tmp` fixtures and signed item files.
- Placeholders such as `PROCESS_ID`, `USER_ADDRESS`, `RECIPIENT`, and local resolver names.
- Operator-only mutations such as route registration, local-name registration, payment ledger changes, and process scheduling.
- Cache, query, match, route, scheduler, payment, recorder, or Arweave state that was assumed but not created by the recipe.
- Extra tools such as `grep`, `sed`, `cat`, `wc`, `node`, and `rebar3` inside runnable blocks.
- HTTP 200 responses that are semantically wrong, including Hyperbuddy shells and recorder reports whose target result is `not_found`.

## Replacement Status

Approved public replacement pages now cover:

- docs-test readiness and schema introspection
- message construction and JSON serialization
- gzip round trips
- inline Lua transforms
- patch key movement
- ANS-104 bundling prerequisites without submitting bytes
- match/query contract inspection without claiming existing matches
- process, scheduler, and push shape inspection without scheduling
- real process reads against the seeded counter fixture
- metering and P4 contract inspection without ledger mutation
- relay contract inspection without arbitrary URL fetches

Operator-only pages remain for recorder debug flights and trusted custom device loading. They intentionally publish no runnable commands until there is a deterministic fixture.

## Test Result

Strict recipe validation passed:

```text
HB=https://docs-test.mystical.computer CURL_EXAMPLE_DOCS_DIR=docs/recipes CURL_EXAMPLE_FAIL_ON_SKIP=1 node scripts/validate-curl-examples.mjs
Summary: 27 passed, 0 failed, 0 skipped
```

The broader docs curl scan is not yet clean:

```text
HB=https://docs-test.mystical.computer node scripts/validate-curl-examples.mjs
Summary: 102 passed, 30 failed, 53 skipped
```

Those failures are outside the approved recipe directory, mostly device/reference examples that still need the recipe-standard treatment or should be marked operator-only.

## Still Missing

- A deterministic match/query workflow that seeds a known index entry, queries it, and proves the result belongs to that fixture.
- A signed ANS-104 item fixture for bundler examples that does not depend on a pre-existing local file.
- A recorder fixture that records a successful structured target request and asserts success, not just HTTP 200.
- Payment recipes with disposable ledger fixtures for balance, topup, gate, and charge flows.
- A publication workflow for replacing quarantined on-weave recipe transactions with standards-compliant versions.
