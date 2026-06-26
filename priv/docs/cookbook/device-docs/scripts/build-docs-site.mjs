import { copyFile, cp, mkdir, readdir, readFile, rm, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const docsDir = path.join(root, 'docs');
const siteDir = path.join(root, 'site');
const distDir = path.join(root, 'dist');

const sectionOrder = [
  'introduction',
  'getting-started',
  'devices',
  'forge',
  'recipes',
  'reference'
];

const sectionTitles = {
  introduction: 'Introduction',
  'getting-started': 'Using These Docs',
  devices: 'Devices',
  forge: 'Device Forge',
  recipes: 'Recipes',
  reference: 'Reference'
};

const sectionHomePaths = {
  introduction: '/introduction/index.md',
  'getting-started': '/getting-started/index.md',
  devices: '/devices/index.md',
  forge: '/forge/index.md',
  recipes: '/recipes/index.md',
  reference: '/reference/glossary.md'
};

const fileOrder = {
  introduction: [
    'index.md',
    'what-is-hyperbeam.md',
    'what-is-ao-core.md',
    'ao-devices.md',
    'pathing-in-ao-core.md'
  ],
  'getting-started': [
    'index.md',
    'example-style.md'
  ]
};

const deviceGroupTitles = {
  'arweave-and-data': 'Arweave And Data',
  'foundations': 'Foundations',
  'compute-and-processes': 'Compute And Processes',
  'codecs-and-formats': 'Codecs And Formats',
  'node-operations': 'Node Operations',
  'auth-and-access': 'Auth And Access',
  'payment-and-metering': 'Payment And Metering',
  'support-and-test': 'Support And Test'
};

const deviceGroupDescriptions = {
  'arweave-and-data': 'Read, bundle, copy, and query Arweave data',
  foundations: 'Messages, meta, relay, naming, and debugging',
  'compute-and-processes': 'Processes, Lua, WASM, scheduling, and composition',
  'codecs-and-formats': 'JSON, gzip, manifests, signatures, and codecs',
  'node-operations': 'Routing, cache, profiles, and node policy',
  'auth-and-access': 'Secrets, cookies, HTTP auth, and hooks',
  'payment-and-metering': 'Payments, metering, and paid device access',
  'support-and-test': 'Recording, debug flights, and test devices'
};

const navItemDescriptions = {
  'getting-started/index.md': 'How to read the local device examples in this corpus',
  'getting-started/example-style.md': 'How hyperpaths, keys, and quoting work',

  'concepts/local-vs-remote-devices.md': 'How nodes load core, pinned, and remote devices',
  'concepts/messages-and-hyperpaths.md': 'How request paths compose message operations',
  'concepts/processes-as-a-recipe.md': 'Processes as reusable device composition workflows',
  'concepts/verification-model.md': 'Trust layers to keep separate when reasoning',
  'concepts/what-devices-are.md': 'What a device is and how paths work',

  'devices/index.md': 'Inventory of core HyperBEAM edge devices by purpose',

  'forge/index.md': 'Overview of the Device Forge workflow',
  'forge/create-a-device.md': 'Author a dev module and define device keys',
  'forge/install-template.md': 'Install the Forge template from HyperBEAM',
  'forge/operator-configuration.md': 'Operator settings for loading, auth, and routes',
  'forge/publish-and-load.md': 'Sign, publish, and load devices on nodes',
  'forge/run-local.md': 'Run a packaged device on a local node',
  'forge/runbook.md': 'End to end Forge packaging and verification runbook',
  'forge/test-package-verify.md': 'Package, verify, and test before you publish',
  'forge/trusted-signers-and-pins.md': 'Trusted signers, pins, and remote load policy',

  'recipes/index.md': 'Use case workflows that combine multiple devices',
  'recipes/arweave-json-to-lua.md': 'Run an inline Lua transform without local files',
  'recipes/bundle-data-locally.md': 'Inspect ANS-104 bundling prerequisites',
  'recipes/create-a-process.md': 'Build a process shaped message from devices',
  'recipes/gzip-round-trip.md': 'Compress and decompress a message body locally',
  'recipes/inspect-transaction-codec.md': 'Inspect Arweave transaction codec commitments',
  'recipes/message-to-json-pipe.md': 'Construct a message and serialize it to JSON',
  'recipes/paid-device-access.md': 'Inspect pricing and metering contracts',
  'recipes/patch-process-state.md': 'Move values between paths before compute runs',
  'recipes/query-local-cache.md': 'Inspect match/query readiness without hidden state',
  'recipes/read-meta-node-info.md': 'Read public meta node identity and build fields',
  'recipes/read-seeded-process-state.md': 'Read a real public counter process fixture',
  'recipes/recorder-debug-flight.md': 'Operator fixture requirements for recorder',
  'recipes/relay-fetch-transform.md': 'Inspect relay contract and route policy',
  'recipes/scheduled-lua-process.md': 'Pattern for a scheduled Lua backed process',

  'reference/device-inventory.md': 'Canonical list of documented edge root devices',
  'reference/example-validation.md': 'Quick smoke tests for docs example commands',
  'reference/glossary.md': 'Terms used across devices, paths, and Forge',
  'reference/process-fixture.md': 'Public process ID used by runnable examples',
  'reference/recipe-audit-2026-06-25.md': 'Current recipe quarantine and validation audit',
  'reference/recipe-standards.md': 'Rules for public runnable recipes'
};

function titleFromSlug(slug) {
  return slug
    .replace(/\.md$/, '')
    .replace(/-/g, ' ')
    .replace(/\bat\b/g, '@')
    .replace(/\b\w/g, (ch) => ch.toUpperCase());
}

async function firstHeading(file) {
  const text = await readFile(file, 'utf8');
  const match = text.match(/^#\s+(.+)$/m);
  return match ? match[1].trim() : titleFromSlug(path.basename(file));
}

function shortNavDescription(section, file) {
  const key = `${section}/${file}`;
  if (navItemDescriptions[key]) return navItemDescriptions[key];
  if (file === 'index.md') return 'Overview of this documentation section';

  const slug = file
    .replace(/\.md$/, '')
    .replace(/-at-[\d.]+[a-z]*$/i, '')
    .split('-')
    .filter((word) => !['a', 'an', 'the', 'and', 'as', 'to', 'with', 'for', 'of'].includes(word));

  return slug
    .slice(0, 6)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');
}

async function mdFiles(dir) {
  const entries = await readdir(dir, { withFileTypes: true });
  return entries
    .filter((entry) => entry.isFile() && entry.name.endsWith('.md'))
    .map((entry) => entry.name)
    .sort((a, b) => {
      if (a === 'index.md') return -1;
      if (b === 'index.md') return 1;
      return a.localeCompare(b);
    });
}

function orderFiles(section, files) {
  const order = fileOrder[section];
  if (!order) return files;
  const rank = new Map(order.map((file, index) => [file, index]));
  return [...files].sort((a, b) => {
    const rankA = rank.has(a) ? rank.get(a) : Number.MAX_SAFE_INTEGER;
    const rankB = rank.has(b) ? rank.get(b) : Number.MAX_SAFE_INTEGER;
    if (rankA !== rankB) return rankA - rankB;
    return a.localeCompare(b);
  });
}

async function buildSection(section) {
  const sectionDir = path.join(docsDir, section);
  const exists = await stat(sectionDir).then((s) => s.isDirectory()).catch(() => false);
  if (!exists) return [];

  const lines = [`- ${sectionTitles[section] ?? titleFromSlug(section)}`];

  if (section === 'devices') {
    const indexFile = path.join(sectionDir, 'index.md');
    lines.push(`  - [Overview](/devices/index.md)`);
    for (const group of Object.keys(deviceGroupTitles)) {
      const groupDir = path.join(sectionDir, group);
      const groupExists = await stat(groupDir).then((s) => s.isDirectory()).catch(() => false);
      if (!groupExists) continue;
      lines.push(`  - ${deviceGroupTitles[group]}`);
      for (const file of await mdFiles(groupDir)) {
        const heading = await firstHeading(path.join(groupDir, file));
        lines.push(`    - [${heading}](/devices/${group}/${file})`);
      }
    }
    await stat(indexFile).catch(() => undefined);
    return lines;
  }

  for (const file of orderFiles(section, await mdFiles(sectionDir))) {
    const label = file === 'index.md' ? 'Overview' : await firstHeading(path.join(sectionDir, file));
    lines.push(`  - [${label}](/${section}/${file})`);
  }

  return lines;
}

async function buildNavItems(section) {
  const sectionDir = path.join(docsDir, section);
  const exists = await stat(sectionDir).then((s) => s.isDirectory()).catch(() => false);
  if (!exists) return [];

  const items = [];

  if (section === 'devices') {
    items.push({
      title: 'Overview',
      href: sectionHomePaths.devices,
      description: shortNavDescription('devices', 'index.md')
    });
    for (const group of Object.keys(deviceGroupTitles)) {
      const groupDir = path.join(sectionDir, group);
      const groupExists = await stat(groupDir).then((s) => s.isDirectory()).catch(() => false);
      if (!groupExists) continue;
      const files = await mdFiles(groupDir);
      if (!files.length) continue;
      const children = [];
      for (const file of files) {
        children.push({
          title: await firstHeading(path.join(groupDir, file)),
          href: `/devices/${group}/${file}`
        });
      }
      items.push({
        title: deviceGroupTitles[group],
        href: `/devices/${group}/${files[0]}`,
        description: deviceGroupDescriptions[group] ?? deviceGroupTitles[group],
        children
      });
    }
    return items;
  }

  for (const file of orderFiles(section, await mdFiles(sectionDir))) {
    const filePath = path.join(sectionDir, file);
    items.push({
      title: file === 'index.md' ? 'Overview' : await firstHeading(filePath),
      href: `/${section}/${file}`,
      description: shortNavDescription(section, file)
    });
  }

  return items;
}

async function writeNavConfig() {
  const sections = [];

  for (const section of sectionOrder) {
    const items = await buildNavItems(section);
    if (!items.length) continue;
    sections.push({
      id: section,
      label: sectionTitles[section] ?? titleFromSlug(section),
      home: sectionHomePaths[section],
      items
    });
  }

  await writeFile(
    path.join(distDir, 'assets', 'nav-sections.json'),
    `${JSON.stringify({ sections }, null, 2)}\n`
  );
}

async function writeSidebar() {
  const rootLines = ['- [Home](/)', ''];
  for (const section of sectionOrder) {
    const title = sectionTitles[section] ?? titleFromSlug(section);
    const homePath = sectionHomePaths[section];
    if (homePath) rootLines.push(`- [${title}](${homePath})`);
  }
  await writeFile(path.join(distDir, '_sidebar.md'), `${rootLines.join('\n').trim()}\n`);

  for (const section of sectionOrder) {
    const sectionLines = await buildSection(section);
    if (!sectionLines.length) continue;
    await writeFile(
      path.join(distDir, section, '_sidebar.md'),
      `${sectionLines.join('\n').trim()}\n`
    );
  }
}

async function vendorDocsify() {
  const assetsDir = path.join(distDir, 'assets');
  await mkdir(assetsDir, { recursive: true });
  const docsifyLib = path.join(root, 'node_modules', 'docsify', 'lib');
  await copyFile(path.join(docsifyLib, 'docsify.min.js'), path.join(assetsDir, 'docsify.min.js'));
  await copyFile(path.join(docsifyLib, 'plugins', 'search.min.js'), path.join(assetsDir, 'search.min.js'));
  await copyFile(path.join(docsifyLib, 'themes', 'vue.css'), path.join(assetsDir, 'docsify-vue.css'));

  const prismDir = path.join(root, 'node_modules', 'prismjs');
  await copyFile(path.join(prismDir, 'themes', 'prism.min.css'), path.join(assetsDir, 'prism.css'));
  for (const language of ['bash', 'json', 'lua', 'erlang', 'markdown', 'http']) {
    await copyFile(
      path.join(prismDir, 'components', `prism-${language}.min.js`),
      path.join(assetsDir, `prism-${language}.min.js`)
    );
  }
}

await rm(distDir, { recursive: true, force: true });
await mkdir(distDir, { recursive: true });
await cp(docsDir, distDir, { recursive: true });
await cp(siteDir, distDir, { recursive: true });
await vendorDocsify();
await writeSidebar();
await writeNavConfig();

const fontsDir = path.join(distDir, 'assets', 'fonts');
const fontsReady = await stat(fontsDir).then((s) => s.isDirectory()).catch(() => false);
if (!fontsReady) {
  throw new Error('Missing dist/assets/fonts — ensure site/assets/fonts is populated before build.');
}

console.log(`Built hash-routed docs site in ${path.relative(root, distDir)}/`);
console.log('Open dist/index.html locally, or run npm run docs:serve.');
