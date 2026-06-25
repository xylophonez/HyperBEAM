#!/usr/bin/env node
import { mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { spawn } from 'node:child_process';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const docsDir = process.env.CURL_EXAMPLE_DOCS_DIR
  ? path.resolve(root, process.env.CURL_EXAMPLE_DOCS_DIR)
  : path.join(root, 'docs');
const timeoutMs = Number(process.env.CURL_EXAMPLE_TIMEOUT_MS || 120000);
const exampleBaseUrl = process.env.HB || 'http://localhost:8734';
const failOnSkip = process.env.CURL_EXAMPLE_FAIL_ON_SKIP === '1';

const skipPattern = new RegExp([
  'USER_ADDRESS',
  'PROCESS_ID',
  'RECIPIENT',
  'SCHEDULER',
  'MODULE_ID',
  'WALLET',
  'wallet\\.json',
  'SIGNED_ITEM',
  'NAME_FROM_YOUR_RESOLVER',
  'replace-with',
  'router\\.example',
  'localhost:8799',
  'ARWEAVE_WALLET',
  'TURBO_',
  '~router@1\\.0/routes',
  '~router@1\\.0/register',
  '~simple-pay@1\\.0/(topup|charge)',
  '~faff@1\\.0',
  '~process@1\\.0',
  '~wasm-64@1\\.0',
  '~wasi@1\\.0',
  '~recorder@1\\.0',
  'commitment-device=ans104@1\\.0',
  'commitment-device=tx@1\\.0',
  '~bundler@1\\.0/item',
  '~copycat@1\\.0/arweave\\?from=.*mode=write',
  'from=\\$TIP&mode=write'
].join('|'));

async function walk(dir) {
  const entries = await readdir(dir, { withFileTypes: true });
  const out = [];
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...await walk(full));
    if (entry.isFile() && entry.name.endsWith('.md')) out.push(full);
  }
  return out.sort((a, b) => a.localeCompare(b));
}

function shellBlocks(markdown) {
  const blocks = [];
  const re = /```(?:sh|bash)\n([\s\S]*?)```/g;
  let match;
  while ((match = re.exec(markdown)) !== null) {
    blocks.push(match[1].trim());
  }
  return blocks;
}

function envAssignments(block) {
  return block
    .split('\n')
    .filter((line) => {
      const trimmed = line.trim();
      return /^[A-Z_][A-Z0-9_]*=(?:"[^"]*"|'[^']*'|[^\s]+)$/.test(trimmed)
        || /^export [A-Z_][A-Z0-9_]*=(?:"[^"]*"|'[^']*'|[^\s]+)$/.test(trimmed);
    });
}

function shouldRun(block) {
  return block.includes('curl')
    && (block.includes('$HB') || block.includes('localhost:8734'))
    && !skipPattern.test(block);
}

function hasUnsetVariables(block, knownAssignments) {
  const assigned = new Set(
    knownAssignments
      .map((line) => line.replace(/^export\s+/, '').split('=')[0])
      .filter(Boolean)
  );
  const vars = [...block.matchAll(/\$([A-Z_][A-Z0-9_]*)/g)].map((m) => m[1]);
  return vars.some((name) => !assigned.has(name) && !['RANDOM'].includes(name));
}

async function runShell(script, cwd) {
  const dir = await mkdtemp(path.join(tmpdir(), 'hb-curl-example-'));
  const scriptPath = path.join(dir, 'run.sh');
  const runnableScript = script.split('http://localhost:8734').join(exampleBaseUrl);
  await writeFile(scriptPath, `set -e\n${runnableScript}\n`);
  return new Promise((resolve) => {
    const child = spawn('timeout', ['-k', '2s', `${Math.ceil(timeoutMs / 1000)}s`, 'bash', scriptPath], {
      cwd,
      env: { ...process.env, HB: exampleBaseUrl },
      stdio: ['ignore', 'pipe', 'pipe']
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.stderr.on('data', (chunk) => { stderr += chunk; });
    child.on('close', async (code, signal) => {
      await rm(dir, { recursive: true, force: true });
      resolve({ code, signal, stdout, stderr });
    });
  });
}

function badOutput(stdout) {
  const normalized = stdout.toLowerCase();
  return normalized.includes('<title>500 - oops.')
    || normalized.includes('<title>404 - page not found.')
    || normalized.includes('<title>hyperbuddy</title>')
    || normalized.includes('command device not found')
    || normalized.includes('"result":["error"')
    || normalized.includes("result => [<<\"error\">>")
    || normalized.includes('device-name-not-resolvable')
    || normalized.includes('device_not_loadable');
}

const files = await walk(docsDir);
const results = [];

for (const file of files) {
  const markdown = await readFile(file, 'utf8');
  const rel = path.relative(root, file);
  const context = [];
  let index = 0;
  for (const block of shellBlocks(markdown)) {
    index += 1;
    context.push(...envAssignments(block));
    if (!block.includes('curl')) continue;
    if (!block.includes('$HB') && !block.includes('localhost:8734')) {
      results.push({ rel, index, status: 'skipped', reason: 'not a local HyperBEAM curl example' });
      continue;
    }
    if (skipPattern.test(block)) {
      results.push({ rel, index, status: 'skipped', reason: 'template/operator/wallet-gated' });
      continue;
    }
    if (hasUnsetVariables(block, context)) {
      results.push({ rel, index, status: 'skipped', reason: 'requires unset shell variable' });
      continue;
    }
    const script = [...context, block].join('\n');
    console.error(`RUN ${rel}#block-${index}`);
    const started = Date.now();
    const run = await runShell(script, root);
    const elapsedMs = Date.now() - started;
    const status = run.code === 0 && !badOutput(run.stdout) ? 'passed' : 'failed';
    results.push({
      rel,
      index,
      status,
      elapsedMs,
      code: run.code,
      signal: run.signal,
      stdout: run.stdout.slice(0, 500).replace(/\s+/g, ' ').trim(),
      stderr: run.stderr.slice(0, 500).replace(/\s+/g, ' ').trim()
    });
  }
}

const passed = results.filter((r) => r.status === 'passed').length;
const failed = results.filter((r) => r.status === 'failed').length;
const skipped = results.filter((r) => r.status === 'skipped').length;

for (const result of results) {
  const loc = `${result.rel}#block-${result.index}`;
  if (result.status === 'passed') {
    console.log(`PASS ${loc} ${result.elapsedMs}ms ${result.stdout}`);
  } else if (result.status === 'skipped') {
    console.log(`SKIP ${loc} ${result.reason}`);
  } else {
    console.log(`FAIL ${loc} code=${result.code} signal=${result.signal || ''}`);
    if (result.stdout) console.log(`  stdout: ${result.stdout}`);
    if (result.stderr) console.log(`  stderr: ${result.stderr}`);
  }
}

console.log(`\nSummary: ${passed} passed, ${failed} failed, ${skipped} skipped`);
process.exitCode = failed > 0 || (failOnSkip && skipped > 0) ? 1 : 0;
