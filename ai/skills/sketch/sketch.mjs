#!/usr/bin/env node
import { createServer } from "node:http";
import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import { extname, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const MAX_PICKS_BYTES = 10_000;
const PICK_LIST = String.raw`(none|\w+-\w+(, \w+-\w+)*)`;
const PICKS_LINE = new RegExp(`^Locked: ${PICK_LIST}\\. Leaning: ${PICK_LIST}\\.$`);
const HOLD_WAIT_MS = 25_000;
const CONTENT_TYPES = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".json": "application/json",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".webp": "image/webp",
  ".gif": "image/gif",
  ".woff2": "font/woff2",
};

async function readBody(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > MAX_PICKS_BYTES) return null;
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString("utf8").trim();
}

async function savePicks(inbox, request, response) {
  const picks = await readBody(request);
  if (!picks || !PICKS_LINE.test(picks)) {
    response.writeHead(400).end();
    return;
  }
  inbox.unread = picks;
  for (const wake of [...inbox.wakers]) wake();
  response.writeHead(204).end();
}

function picksOrTimeout(inbox, response, holdMs) {
  return new Promise((resolveWait) => {
    const wake = () => {
      clearTimeout(timer);
      inbox.wakers.delete(wake);
      resolveWait();
    };
    const timer = setTimeout(wake, holdMs);
    inbox.wakers.add(wake);
    response.once("close", wake);
  });
}

async function takePicks(inbox, response, holdMs) {
  if (inbox.unread === null) await picksOrTimeout(inbox, response, holdMs);
  if (response.destroyed) return;
  if (inbox.unread === null) {
    response.writeHead(204).end();
    return;
  }
  const picks = inbox.unread;
  inbox.unread = null;
  response.writeHead(200, { "content-type": "text/plain; charset=utf-8" }).end(picks);
}

async function sendFile(folder, request, response) {
  const pathname = decodeURIComponent(new URL(request.url, "http://sketch").pathname);
  const requested = resolve(folder, "." + pathname);
  if (requested !== folder && !requested.startsWith(folder + sep)) {
    response.writeHead(403).end();
    return;
  }
  const file = pathname.endsWith("/") ? join(requested, "index.html") : requested;
  const info = await stat(file).catch(() => null);
  if (!info?.isFile()) {
    response.writeHead(404).end();
    return;
  }
  response.writeHead(200, {
    "content-type": CONTENT_TYPES[extname(file).toLowerCase()] ?? "application/octet-stream",
    "content-length": info.size,
    "cache-control": "no-store",
    etag: `"${info.mtimeMs}-${info.size}"`,
  });
  if (request.method === "HEAD") response.end();
  else createReadStream(file).pipe(response);
}

export function serve(folderPath, port, holdMs = HOLD_WAIT_MS) {
  const folder = resolve(folderPath);
  const inbox = { unread: null, wakers: new Set() };
  const server = createServer(async (request, response) => {
    const isPicksRoute = request.url.split("?")[0].endsWith("/picks");
    try {
      if (isPicksRoute && request.method === "POST") await savePicks(inbox, request, response);
      else if (isPicksRoute && request.method === "GET") await takePicks(inbox, response, holdMs);
      else if (request.method === "GET" || request.method === "HEAD") await sendFile(folder, request, response);
      else response.writeHead(405).end();
    } catch {
      response.writeHead(500).end();
    }
  });
  return new Promise((ready) => server.listen(port, "127.0.0.1", () => ready(server)));
}

export async function waitForPicks(port) {
  for (;;) {
    const response = await fetch(`http://127.0.0.1:${port}/picks`);
    if (response.status === 200) return response.text();
    if (response.status !== 204) throw new Error(`The sketch server on port ${port} replied ${response.status}`);
  }
}

const USAGE = "Usage: sketch.mjs serve <folder> <port> | sketch.mjs wait <port>";

async function main([command, ...rest]) {
  if (command === "serve" && rest[0] && Number(rest[1]) > 0) {
    await serve(rest[0], Number(rest[1]));
    console.log(`Serving ${resolve(rest[0])} on http://127.0.0.1:${rest[1]}/`);
  } else if (command === "wait" && Number(rest[0]) > 0) {
    console.log(await waitForPicks(Number(rest[0])));
  } else {
    console.error(USAGE);
    process.exitCode = 2;
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await main(process.argv.slice(2));
}
