#!/usr/bin/env node
/**
 * gen_fixtures.mjs — generate and canonicalize Lexical EditorState fixtures.
 *
 * The Dart port's compatibility contract is "fixed point on canonical fixtures".
 * This script is the only thing that may define "canonical": it runs documents
 * through the real Lexical engine, so derived fields (paragraph.textFormat,
 * paragraph.textStyle, ...) and normalization are whatever upstream actually does
 * rather than what anyone believed it does.
 *
 * Setup (in a scratch dir, not your Dart package):
 *   npm init -y
 *   npm install lexical @lexical/headless @lexical/rich-text @lexical/list \
 *               @lexical/link @lexical/code @lexical/table @lexical/mark \
 *               @lexical/hashtag @lexical/overflow
 *
 * Usage:
 *   node gen_fixtures.mjs --generate <outdir>
 *       Write the built-in corpus (one JSON file per case) plus manifest.json.
 *
 *   node gen_fixtures.mjs --canonicalize <indir> [--out <outdir>]
 *       Read every *.json in <indir>, push it through Lexical, write the canonical
 *       form. Use this on documents exported from your real web app — that corpus
 *       is worth more than any synthetic one. Defaults to in-place.
 *
 *   node gen_fixtures.mjs --check <dir>
 *       Verify every *.json in <dir> is already canonical (a fixed point). Use in
 *       CI to detect upstream drift after a Lexical upgrade.
 *
 * Exit codes: 0 ok, 1 usage error, 2 at least one document failed or is not canonical.
 */

import {readdir, readFile, writeFile, mkdir} from 'node:fs/promises';
import {readFileSync} from 'node:fs';
import {join, basename, sep} from 'node:path';
import {createRequire} from 'node:module';

const require = createRequire(import.meta.url);

/* ------------------------------------------------------------------ *
 * Node registration. Optional packages degrade gracefully so the
 * script stays usable with a partial install.
 * ------------------------------------------------------------------ */

const OPTIONAL = [
  ['@lexical/rich-text', ['HeadingNode', 'QuoteNode']],
  ['@lexical/list', ['ListNode', 'ListItemNode']],
  ['@lexical/link', ['LinkNode', 'AutoLinkNode']],
  ['@lexical/code', ['CodeNode', 'CodeHighlightNode']],
  ['@lexical/table', ['TableNode', 'TableRowNode', 'TableCellNode']],
  ['@lexical/mark', ['MarkNode']],
  ['@lexical/hashtag', ['HashtagNode']],
  ['@lexical/overflow', ['OverflowNode']],
];

async function collectNodes() {
  const nodes = [];
  const missing = [];
  const mods = {};
  for (const [pkg, names] of OPTIONAL) {
    try {
      const mod = await import(pkg);
      mods[pkg] = mod;
      for (const n of names) {
        if (mod[n]) nodes.push(mod[n]);
      }
    } catch {
      missing.push(pkg);
    }
  }
  return {nodes, missing, mods};
}

/**
 * Resolve lexical's version. `require('lexical/package.json')` fails because the
 * package's "exports" map does not expose that subpath, so resolve the entry point
 * and walk up to the package root instead.
 */
function lexicalVersion() {
  try {
    return require('lexical/package.json').version;
  } catch {
    /* exports-restricted, fall through */
  }
  try {
    const entry = require.resolve('lexical');
    const marker = `${sep}node_modules${sep}lexical${sep}`;
    const idx = entry.lastIndexOf(marker);
    if (idx !== -1) {
      const pkgRoot = entry.slice(0, idx + marker.length);
      return JSON.parse(readFileSync(join(pkgRoot, 'package.json'), 'utf8')).version;
    }
  } catch {
    /* fall through */
  }
  return 'unknown';
}

/* ------------------------------------------------------------------ *
 * Canonicalization
 * ------------------------------------------------------------------ */

async function makeEditor(nodes) {
  const {createHeadlessEditor} = await import('@lexical/headless');
  return createHeadlessEditor({
    nodes,
    onError: (e) => {
      throw e;
    },
  });
}

/**
 * Push a serialized EditorState through Lexical and return its canonical form.
 * A fresh editor per document keeps cases isolated — a leaked node map between
 * documents would silently contaminate fixtures.
 */
async function canonicalize(json, nodes) {
  const editor = await makeEditor(nodes);
  const text = typeof json === 'string' ? json : JSON.stringify(json);
  const parsed = editor.parseEditorState(text);
  if (parsed.isEmpty()) {
    // setEditorState throws on an empty state (root-only, no selection). That
    // shape is legal on the wire, so canonicalize it as itself rather than
    // failing the whole run.
    return wireForm(parsed.toJSON());
  }
  editor.setEditorState(parsed);
  return wireForm(editor.getEditorState().toJSON());
}

/**
 * toJSON() returns live objects that may carry keys whose value is `undefined`
 * (listitem.checked outside check lists, tablerow.height, code.language, ...).
 * Object.keys() counts those keys; JSON.stringify erases them. Comparing a raw
 * toJSON() result against a parsed file therefore reports differences that do
 * not exist on the wire. Round-tripping through the serializer collapses the
 * in-memory shape onto the shape that is actually persisted, which is the only
 * shape the Dart port can observe.
 */
function wireForm(value) {
  return JSON.parse(JSON.stringify(value));
}

function stable(value) {
  return JSON.stringify(value, null, 2) + '\n';
}

function deepEquals(a, b) {
  if (a === b) return true;
  if (Array.isArray(a) && Array.isArray(b)) {
    return a.length === b.length && a.every((v, i) => deepEquals(v, b[i]));
  }
  if (a && b && typeof a === 'object' && typeof b === 'object') {
    const ka = Object.keys(a);
    const kb = Object.keys(b);
    if (ka.length !== kb.length) return false;
    // containsKey semantics: absent must not equal present-and-null
    return ka.every((k) => Object.hasOwn(b, k) && deepEquals(a[k], b[k]));
  }
  return false;
}

/* ------------------------------------------------------------------ *
 * Built-in corpus
 *
 * Each case is built with the real APIs rather than hand-written JSON, so
 * the output is canonical by construction. Cases are chosen to pin down the
 * things a Dart decoder gets wrong: bitmask combinations, omit-vs-null,
 * derived fields, empty containers, and nesting.
 * ------------------------------------------------------------------ */

async function buildCorpus(mods) {
  const L = await import('lexical');
  const rt = mods['@lexical/rich-text'];
  const li = mods['@lexical/list'];
  const lk = mods['@lexical/link'];
  const cd = mods['@lexical/code'];
  const tb = mods['@lexical/table'];
  const mk = mods['@lexical/mark'];
  const ht = mods['@lexical/hashtag'];

  const cases = [];
  const add = (name, build, requires = []) => {
    if (requires.some((m) => !m)) return;
    cases.push({name, build});
  };

  add('empty-root', () => {});

  add('single-paragraph', (root) => {
    const p = L.$createParagraphNode();
    p.append(L.$createTextNode('Hallo Welt'));
    root.append(p);
  });

  add('empty-paragraph', (root) => {
    root.append(L.$createParagraphNode());
  });

  add('text-format-matrix', (root) => {
    const formats = [
      'bold', 'italic', 'strikethrough', 'underline', 'code',
      'subscript', 'superscript', 'highlight',
      'lowercase', 'uppercase', 'capitalize',
    ];
    for (const f of formats) {
      const p = L.$createParagraphNode();
      const t = L.$createTextNode(f);
      try {
        t.setFormat(f);
      } catch {
        continue;
      }
      p.append(t);
      root.append(p);
    }
  });

  add('text-format-combinations', (root) => {
    const combos = [
      ['bold', 'italic'],
      ['bold', 'strikethrough'],
      ['italic', 'underline', 'code'],
      ['bold', 'italic', 'underline', 'strikethrough'],
    ];
    for (const combo of combos) {
      const p = L.$createParagraphNode();
      const t = L.$createTextNode(combo.join('+'));
      t.setFormat(combo[0]);
      for (const f of combo.slice(1)) t.toggleFormat(f);
      p.append(t);
      root.append(p);
    }
  });

  add('text-modes-and-style', (root) => {
    const p = L.$createParagraphNode();
    const token = L.$createTextNode('@token');
    token.setMode('token');
    const seg = L.$createTextNode('segmented text');
    seg.setMode('segmented');
    const styled = L.$createTextNode('styled');
    styled.setStyle('color: #ff0000; font-size: 14px; font-family: Inter');
    p.append(L.$createTextNode('normal '), token, L.$createTextNode(' '), seg, L.$createTextNode(' '), styled);
    root.append(p);
  });

  add('linebreak-and-tab', (root) => {
    const p = L.$createParagraphNode();
    p.append(
      L.$createTextNode('vor'),
      L.$createLineBreakNode(),
      L.$createTextNode('nach'),
      L.$createTabNode(),
      L.$createTextNode('tabbed'),
    );
    root.append(p);
  });

  add('derived-textformat', (root) => {
    // The trailing child's format is what paragraph.textFormat must derive from.
    const p = L.$createParagraphNode();
    const a = L.$createTextNode('plain ');
    const b = L.$createTextNode('bold+code');
    b.setFormat('bold');
    b.toggleFormat('code');
    p.append(a, b);
    root.append(p);
  });

  add('alignment-and-indent', (root) => {
    for (const align of ['left', 'center', 'right', 'justify', 'start', 'end']) {
      const p = L.$createParagraphNode();
      p.append(L.$createTextNode(align));
      p.setFormat(align);
      root.append(p);
    }
    const indented = L.$createParagraphNode();
    indented.append(L.$createTextNode('indent 3'));
    indented.setIndent(3);
    root.append(indented);
  });

  add('direction-rtl', (root) => {
    const p = L.$createParagraphNode();
    p.append(L.$createTextNode('سلاو دنیا'));
    p.setDirection('rtl');
    root.append(p);
    const ltr = L.$createParagraphNode();
    ltr.append(L.$createTextNode('Silav dinya'));
    ltr.setDirection('ltr');
    root.append(ltr);
  });

  add('unicode-edge-cases', (root) => {
    const p = L.$createParagraphNode();
    p.append(
      L.$createTextNode('emoji-zwj: \u{1F469}\u200D\u{1F4BB}'),
      L.$createLineBreakNode(),
      L.$createTextNode('skin-tone: \u{1F44D}\u{1F3FD}'),
      L.$createLineBreakNode(),
      L.$createTextNode('combining: e\u0301 vs \u00e9'),
      L.$createLineBreakNode(),
      L.$createTextNode('kurdî: çêwtî û pêşketin'),
      L.$createLineBreakNode(),
      L.$createTextNode('cjk: 日本語のテキスト'),
    );
    root.append(p);
  });

  add('headings-and-quote', (root) => {
    for (const tag of ['h1', 'h2', 'h3', 'h4', 'h5', 'h6']) {
      const h = rt.$createHeadingNode(tag);
      h.append(L.$createTextNode(tag.toUpperCase()));
      root.append(h);
    }
    const q = rt.$createQuoteNode();
    q.append(L.$createTextNode('Ein Zitat'));
    root.append(q);
  }, [rt]);

  add('lists', (root) => {
    const bullet = li.$createListNode('bullet');
    const b1 = li.$createListItemNode();
    b1.append(L.$createTextNode('erster Punkt'));
    const b2 = li.$createListItemNode();
    b2.append(L.$createTextNode('zweiter Punkt'));
    bullet.append(b1, b2);
    root.append(bullet);

    const numbered = li.$createListNode('number', 3);
    const n1 = li.$createListItemNode();
    n1.append(L.$createTextNode('start bei drei'));
    numbered.append(n1);
    root.append(numbered);

    // `checked` is present only for check lists — an omit-vs-present case.
    const check = li.$createListNode('check');
    const c1 = li.$createListItemNode(true);
    c1.append(L.$createTextNode('erledigt'));
    const c2 = li.$createListItemNode(false);
    c2.append(L.$createTextNode('offen'));
    check.append(c1, c2);
    root.append(check);
  }, [li]);

  add('nested-list', (root) => {
    const outer = li.$createListNode('bullet');
    const item = li.$createListItemNode();
    item.append(L.$createTextNode('außen'));
    const holder = li.$createListItemNode();
    const inner = li.$createListNode('bullet');
    const innerItem = li.$createListItemNode();
    innerItem.append(L.$createTextNode('innen'));
    inner.append(innerItem);
    holder.append(inner);
    outer.append(item, holder);
    root.append(outer);
  }, [li]);

  add('links', (root) => {
    const p = L.$createParagraphNode();
    // title stays null and is emitted as an explicit null.
    const bare = lk.$createLinkNode('https://lexical.dev');
    bare.append(L.$createTextNode('bare'));
    const full = lk.$createLinkNode('https://example.org', {
      rel: 'noreferrer noopener',
      target: '_blank',
      title: 'Ein Titel',
    });
    full.append(L.$createTextNode('full'));
    p.append(bare, L.$createTextNode(' '), full);
    root.append(p);

    if (lk.$createAutoLinkNode) {
      const p2 = L.$createParagraphNode();
      const auto = lk.$createAutoLinkNode('https://auto.example');
      auto.append(L.$createTextNode('auto.example'));
      p2.append(auto);
      root.append(p2);
    }
  }, [lk]);

  add('code-block', (root) => {
    const c = cd.$createCodeNode('dart');
    c.append(L.$createTextNode('void main() {\n  print("hi");\n}'));
    root.append(c);
  }, [cd]);

  add('table', (root) => {
    root.append(tb.$createTableNodeWithDimensions(2, 3, true));
  }, [tb]);

  add('mark-and-hashtag', (root) => {
    const p = L.$createParagraphNode();
    if (mk) {
      const m = mk.$createMarkNode(['comment-1', 'comment-2']);
      m.append(L.$createTextNode('markiert'));
      p.append(m, L.$createTextNode(' '));
    }
    if (ht) {
      p.append(ht.$createHashtagNode('#flutter'));
    }
    root.append(p);
  }, [mk || ht]);

  add('deep-nesting', (root) => {
    // Guards against a recursive decoder blowing the stack and pins indent handling.
    let depth = 0;
    const outer = li.$createListNode('bullet');
    let current = outer;
    while (depth < 12) {
      const item = li.$createListItemNode();
      const nested = li.$createListNode('bullet');
      const leaf = li.$createListItemNode();
      leaf.append(L.$createTextNode(`Ebene ${depth}`));
      nested.append(leaf);
      item.append(nested);
      current.append(item);
      current = nested;
      depth++;
    }
    root.append(outer);
  }, [li]);

  add('mixed-document', (root) => {
    const h = rt.$createHeadingNode('h2');
    h.append(L.$createTextNode('Bericht'));
    root.append(h);
    const p = L.$createParagraphNode();
    const bold = L.$createTextNode('wichtig');
    bold.setFormat('bold');
    p.append(L.$createTextNode('Etwas '), bold, L.$createTextNode(' Text.'));
    root.append(p);
    const q = rt.$createQuoteNode();
    q.append(L.$createTextNode('Zitiert'));
    root.append(q);
    const list = li.$createListNode('bullet');
    const item = li.$createListItemNode();
    const link = lk.$createLinkNode('https://lexical.dev');
    link.append(L.$createTextNode('Quelle'));
    item.append(link);
    list.append(item);
    root.append(list);
  }, [rt, li, lk]);

  return cases;
}

async function generate(outdir, nodes, mods) {
  await mkdir(outdir, {recursive: true});
  const L = await import('lexical');
  const cases = await buildCorpus(mods);
  const written = [];
  let failed = 0;

  for (const {name, build} of cases) {
    try {
      const editor = await makeEditor(nodes);
      editor.update(() => {
        const root = L.$getRoot();
        root.clear();
        build(root);
      }, {discrete: true});
      const produced = editor.getEditorState().toJSON();
      // Round-trip once more so the file is guaranteed to be a fixed point.
      const canonical = await canonicalize(produced, nodes);
      if (!deepEquals(produced, canonical)) {
        console.warn(`  ! ${name}: not a fixed point after construction; storing canonical form`);
      }
      const file = join(outdir, `${name}.json`);
      await writeFile(file, stable(canonical), 'utf8');
      written.push(`${name}.json`);
      console.log(`  + ${name}.json`);
    } catch (err) {
      failed++;
      console.error(`  x ${name}: ${err.message}`);
    }
  }

  await writeFile(
    join(outdir, 'manifest.json'),
    stable({
      generator: 'gen_fixtures.mjs',
      lexicalVersion: lexicalVersion(),
      generatedAt: new Date().toISOString(),
      fixtures: written,
    }),
    'utf8',
  );
  console.log(`\n${written.length} fixture(s) written to ${outdir} (lexical ${lexicalVersion()})`);
  return failed === 0;
}

async function jsonFilesIn(dir) {
  const entries = await readdir(dir, {withFileTypes: true});
  return entries
    .filter((e) => e.isFile() && e.name.endsWith('.json') && e.name !== 'manifest.json')
    .map((e) => join(dir, e.name));
}

async function canonicalizeDir(indir, outdir, nodes) {
  await mkdir(outdir, {recursive: true});
  const files = await jsonFilesIn(indir);
  let failed = 0;
  for (const file of files) {
    try {
      const raw = await readFile(file, 'utf8');
      const canonical = await canonicalize(raw, nodes);
      const changed = !deepEquals(JSON.parse(raw), canonical);
      await writeFile(join(outdir, basename(file)), stable(canonical), 'utf8');
      console.log(`  ${changed ? '~' : '='} ${basename(file)}${changed ? ' (normalized)' : ''}`);
    } catch (err) {
      failed++;
      console.error(`  x ${basename(file)}: ${err.message}`);
    }
  }
  console.log(`\n${files.length} file(s) processed, ${failed} failed`);
  return failed === 0;
}

async function checkDir(dir, nodes) {
  const files = await jsonFilesIn(dir);
  let bad = 0;
  for (const file of files) {
    try {
      const parsed = JSON.parse(await readFile(file, 'utf8'));
      const canonical = await canonicalize(parsed, nodes);
      if (deepEquals(parsed, canonical)) {
        console.log(`  ok   ${basename(file)}`);
      } else {
        bad++;
        console.error(`  DRIFT ${basename(file)} — not canonical for lexical ${lexicalVersion()}`);
      }
    } catch (err) {
      bad++;
      console.error(`  FAIL ${basename(file)}: ${err.message}`);
    }
  }
  console.log(`\n${files.length} checked, ${bad} not canonical`);
  return bad === 0;
}

/* ------------------------------------------------------------------ *
 * CLI
 * ------------------------------------------------------------------ */

function usage() {
  console.log(`gen_fixtures.mjs — Lexical fixture generator / canonicalizer

  --generate <outdir>              write the built-in corpus
  --canonicalize <indir> [--out d] canonicalize existing fixtures (default: in place)
  --check <dir>                    verify fixtures are canonical (for CI)
  --help
`);
}

async function main() {
  const argv = process.argv.slice(2);
  if (argv.length === 0 || argv.includes('--help') || argv.includes('-h')) {
    usage();
    return 0;
  }

  const flag = (name) => {
    const i = argv.indexOf(name);
    return i === -1 ? undefined : argv[i + 1];
  };

  const {nodes, missing, mods} = await collectNodes();
  if (missing.length) {
    console.warn(`note: optional packages not installed, related cases skipped: ${missing.join(', ')}\n`);
  }

  const gen = flag('--generate');
  const canon = flag('--canonicalize');
  const check = flag('--check');

  if (gen) return (await generate(gen, nodes, mods)) ? 0 : 2;
  if (canon) return (await canonicalizeDir(canon, flag('--out') ?? canon, nodes)) ? 0 : 2;
  if (check) return (await checkDir(check, nodes)) ? 0 : 2;

  usage();
  return 1;
}

main().then(
  (code) => process.exit(code),
  (err) => {
    console.error(err);
    process.exit(2);
  },
);
