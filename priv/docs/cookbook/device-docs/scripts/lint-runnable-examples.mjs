#!/usr/bin/env node
import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const docsDir = path.join(root, 'docs');
const processFixtureId = 'co-MIhejkMR8v3-oIvW8m_u3YfV7zXoII0ja1wk-IOo';
const inspectNote = 'Inspect workflow examples show request, configuration, or operator command shapes.';

const publicLanguagePattern = new RegExp([
  '\\\\bTODO\\\\b',
  '\\\\bFIXME\\\\b',
  '\\\\bWIP\\\\b',
  'fixture needed',
  'we need',
  'for now',
  'not yet',
  'copy/paste',
  'copy-paste',
  'pretending',
  'not safe to fake',
  'fixture-missing',
  'operator-only guidance',
  'Use this as',
  'Do not publish',
  'do not publish',
  'previous recipe',
  'not acceptable',
  'bad-pattern',
  'copycat state',
  'old Arweave',
  'Until that fixture exists',
  'should not be'
].join('|'), 'i');

const shellRiskPatterns = [
  /USER_ADDRESS/,
  /RECIPIENT/,
  /WALLET/,
  /wallet\.json/,
  /SIGNED_ITEM/,
  /NAME_FROM_YOUR_RESOLVER/,
  /<[^>\n]+>/,
  /\/tmp\//,
  /\$\(/,
  /\bgrep\b/,
  /\bsed\b/,
  /\bawk\b/,
  /\btee\b/,
  /\bwc\b/,
  /\bcat\b/,
  /\brebar3\b/,
  /\baos\b/,
  /\bnpm\s+(?:i|install)\b/,
  /ARWEAVE_WALLET/,
  /TURBO_/,
  /~bundler@1\.0\/item/,
  /~simple-pay@1\.0\/(?:topup|charge)/,
  /~router@1\.0\/(?:routes|register)/,
  /~recorder@1\.0/,
  /commitment-device=ans104@1\.0/
];

const commandTextFencePattern = /```text\n[\s\S]*?(curl |cat >|rebar3 |aos |npm |wallet|SIGNED|ARWEAVE|\/tmp\/)[\s\S]*?```/;

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

function blockLine(markdown, index) {
  return markdown.slice(0, index).split('\n').length;
}

function riskyShell(block) {
  const test = (text) => shellRiskPatterns.some((pattern) => pattern.test(text));
  if (block.includes(processFixtureId)) {
    return test(block.replace(/PROCESS_ID="[^"]+"/g, ''));
  }
  return test(block);
}

const files = await walk(docsDir);
const errors = [];

for (const file of files) {
  const markdown = await readFile(file, 'utf8');
  const rel = path.relative(root, file);
  const languageMatch = publicLanguagePattern.exec(markdown);
  if (languageMatch) {
    errors.push(`${rel}:${blockLine(markdown, languageMatch.index)} public wording contains "${languageMatch[0]}"`);
  }

  const isRecipe = rel.startsWith('docs/recipes/');
  for (const match of markdown.matchAll(/```(?:bash|sh)\n([\s\S]*?)```/g)) {
    const block = match[1];
    const line = blockLine(markdown, match.index);
    if (!block.includes('curl')) {
      errors.push(`${rel}:${line} shell fence is not a curl example; use text for inspect workflows`);
      continue;
    }
    if (!isRecipe && !block.includes('$HB') && !block.includes('localhost:8734')) {
      errors.push(`${rel}:${line} non-recipe shell fence must target the local HyperBEAM example node`);
    }
    if (riskyShell(block)) {
      errors.push(`${rel}:${line} shell fence contains local files, placeholders, extra tools, signing, or operator-only state`);
    }
  }

  const isDeviceOrForge = rel.startsWith('docs/devices/') || rel.startsWith('docs/forge/');
  if (isDeviceOrForge && commandTextFencePattern.test(markdown) && !markdown.includes(inspectNote)) {
    errors.push(`${rel}:1 command-shaped text examples need the inspect-workflow note`);
  }
}

if (errors.length) {
  console.error('Runnable example lint failed:');
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`Runnable example lint passed for ${files.length} Markdown files`);
