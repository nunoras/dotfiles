#!/usr/bin/env node
import { spawn } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, mkdtempSync, rmSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const [, , pageUrl, fileArg] = process.argv;
if (!pageUrl || !fileArg) {
  console.error('usage: gh-attach.mjs <github pr or issue url> <file>');
  process.exit(1);
}
const file = resolve(fileArg);
if (!existsSync(file)) {
  console.error(`no such file: ${file}`);
  process.exit(1);
}

const source = join(homedir(), '.config', 'chromium');
const profile = mkdtempSync(join(tmpdir(), 'gh-attach-'));
mkdirSync(join(profile, 'Default'));
cpSync(join(source, 'Local State'), join(profile, 'Local State'));
for (const name of ['Cookies', 'Preferences']) cpSync(join(source, 'Default', name), join(profile, 'Default', name));
const port = 9300 + Math.floor(Math.random() * 600);
const chrome = spawn('chromium', [
  '--headless=new', '--password-store=gnome-libsecret', `--user-data-dir=${profile}`,
  `--remote-debugging-port=${port}`, '--no-first-run', 'about:blank',
], { stdio: 'ignore' });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function finish(code, message) {
  (code ? console.error : console.log)(message);
  const exited = new Promise((r) => chrome.once('exit', r));
  chrome.kill();
  await exited;
  rmSync(profile, { recursive: true, force: true, maxRetries: 5 });
  process.exit(code);
}

async function openTab(url) {
  for (let k = 0; k < 40; k++) {
    const tab = await fetch(`http://localhost:${port}/json/new?${encodeURIComponent(url)}`, { method: 'PUT' })
      .then((r) => r.json())
      .catch(() => undefined);
    if (tab) return tab;
    await sleep(250);
  }
  return undefined;
}

async function connect(tab) {
  const ws = new WebSocket(tab.webSocketDebuggerUrl);
  await new Promise((r) => ws.addEventListener('open', r, { once: true }));
  let id = 0;
  const pending = new Map();
  ws.addEventListener('message', (e) => {
    const m = JSON.parse(e.data);
    if (m.id && pending.has(m.id)) {
      pending.get(m.id)(m);
      pending.delete(m.id);
    }
  });
  const send = (method, params = {}) =>
    new Promise((r) => {
      const i = ++id;
      pending.set(i, r);
      ws.send(JSON.stringify({ id: i, method, params }));
    });
  const evaluate = async (expression) =>
    (await send('Runtime.evaluate', { expression, returnByValue: true })).result?.result?.value;
  return { send, evaluate, close: () => ws.close() };
}

const commentInput = 'form:has(#new_comment_field) input[type=file]';
const findUrl = `document.querySelector("#new_comment_field")?.value
  .match(/https:\\/\\/github\\.com\\/user-attachments\\/assets\\/[\\w-]+/)?.[0] ?? ""`;
const pageState = `location.href + " | " + document.title + " | "
  + [...document.querySelectorAll("textarea")].map((t) => t.name + ": " + t.value.slice(0, 120)).join(" / ")`;

async function upload() {
  const tab = await openTab(pageUrl);
  if (!tab) return { failure: 'chromium did not start' };
  const { send, evaluate, close } = await connect(tab);
  try {
    await send('Page.enable');
    await send('DOM.enable');
    await send('Runtime.enable');
    const ready = `!!document.querySelector(${JSON.stringify(commentInput)}) && !!customElements.get('file-attachment')`;
    for (let k = 0; k < 60 && !(await evaluate(ready)); k++) await sleep(500);
    if (!(await evaluate("document.querySelector('meta[name=user-login]')?.content ?? ''"))) {
      return { failure: 'not signed in to GitHub in ~/.config/chromium', fatal: true };
    }
    const { root } = (await send('DOM.getDocument', { depth: -1, pierce: true })).result;
    const input = (await send('DOM.querySelector', { nodeId: root.nodeId, selector: commentInput })).result;
    if (!input?.nodeId) return { failure: `no comment box file input on ${await evaluate(pageState)}` };
    await sleep(2000);
    await send('DOM.setFileInputFiles', { nodeId: input.nodeId, files: [file] });
    for (let k = 0; k < 60; k++) {
      await sleep(1000);
      const url = await evaluate(findUrl);
      if (url) return { url };
    }
    return { failure: `upload gave no attachment url on ${await evaluate(pageState)}` };
  } finally {
    close();
    await fetch(`http://localhost:${port}/json/close/${tab.id}`).catch(() => undefined);
  }
}

let result;
for (let attempt = 1; attempt <= 4; attempt++) {
  result = await upload();
  if (result.url || result.fatal) break;
  console.error(`attempt ${attempt}: ${result.failure}`);
}
await (result.url ? finish(0, result.url) : finish(4, result.failure));
