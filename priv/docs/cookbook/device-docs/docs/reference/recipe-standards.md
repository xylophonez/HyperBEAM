# Recipe Standards

Recipes are inherited examples. Treat every runnable block as production-facing API guidance.

## Required For Public Recipes

- Use `curl -fsS` so HTTP errors fail validation.
- Set `HB="${HB:-http://localhost:8734}"` inside every runnable block.
- Keep each block self-contained. If a later step needs data, the earlier step must create it in the same recipe.
- Use only shell builtins and `curl` in runnable blocks.
- Use deterministic public fixtures or read-only introspection routes.
- Use the seeded process fixture for process read examples that do not create their own process.
- State the expected result in prose immediately after the command.
- Include every required setup step before the command that depends on it.
- Validate against docs-test before publishing or re-enabling an on-weave recipe.

## Runnable Blocks In Device Docs

Use `bash` or `sh` fences only for examples that are intended to be executed by the validator. Use `text` for operator walkthroughs, configuration snippets, expected failure examples, local-file workflows, wallet/signing flows, and examples that require seeded state outside the block.

The broad docs validator treats every `bash` or `sh` curl block as a public example. A page can still document setup-dependent behavior, but that setup belongs in prose or `text` fences until a deterministic fixture exists.

## Not Acceptable In Public Recipes

- Placeholders such as `PROCESS_ID`, `USER_ADDRESS`, `RECIPIENT`, `WALLET`, or `NAME_FROM_YOUR_RESOLVER`.
- Commands that assume `/tmp` files, local project directories, wallet files, signed item files, or prior shell history.
- Extra command-line tools such as `jq`, `grep`, `sed`, `awk`, `cat`, `wc`, `node`, or `rebar3` in runnable blocks.
- Operator mutations such as route registration, local-name registration, ledgers, topups, charges, process scheduling, bundler submission, cache writes, or recorder flights against private requests.
- Recipes that pass because a node already has arbitrary cache, query, route, scheduler, payment, or process state.
- HTTP 200 responses that are semantically wrong, including Hyperbuddy shells, `not_found` recordings, or error JSON.

## Workflow Recipes

A recipe may be a workflow when setup is necessary. In that case, step one must create or import the fixture and the final step must prove the fixture is the one being read. For example, a match/query recipe must seed an index with known data before asking whether entries exist. A bundler recipe must create signed item bytes before submitting them.

If the setup requires operator authority, wallets, signing keys, node config, or mutable production state, keep the recipe out of the public runnable corpus and move it to operator documentation or CI fixtures.

## Seeded Process Fixture

Use `co-MIhejkMR8v3-oIvW8m_u3YfV7zXoII0ja1wk-IOo` for public process read examples that need an existing process. The process exposes `counter`, `status`, `name`, `version`, and `lastupdate` through `process@1.0/compute`.

Do not publish the node used to seed the fixture. docs-test resolves the fixture through operator routing.

## Blacklist Policy

docs-test loads a recipe blacklist from operator config. A blacklisted recipe can be matched by transaction ID or by `device` plus `slug`. Re-enable a recipe only after:

- Its replacement Markdown follows this standard.
- The curl validator passes with zero failures.
- Strict recipe validation has zero skips for the approved recipe directory.
- Any stateful setup is owned by the recipe and can be repeated on a fresh node.

## Review Checklist

- Can a reader run the first block in a fresh shell?
- Does every block run against `HB=https://docs-test.mystical.computer`?
- Does `curl -fsS` fail if the endpoint is missing?
- Is the expected output observable without another tool?
- Are all prerequisites created by the recipe itself?
- Are operator-only actions clearly kept out of public runnable examples?
