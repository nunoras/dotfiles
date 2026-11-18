#!/usr/bin/env node
import { createServer } from "node:http";
import { createReadStream, watchFile, unwatchFile } from "node:fs";
import { readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import { extname, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const PICKS_FILE = "picks.txt";
const MAX_PICKS_BYTES = 10_000;
const PICK_LIST = String.raw`(none|\w+-\w+(, \w+-\w+)*)`;
const PICKS_LINE = new RegExp(`^Locked: ${PICK_LIST}\\. Leaning: ${PICK_LIST}\\.$`);
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

async function savePicks(folder, request, response) {
  const picks = await readBody(request);
  if (!picks || !PICKS_LINE.test(picks)) {
    response.writeHead(400).end();
    return;
  }
  const arriving = join(folder, PICKS_FILE + ".new");
  await writeFile(arriving, picks + "\n");
  await rename(arriving, join(folder, PICKS_FILE));
  response.writeHead(204).end();
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

export function serve(folderPath, port) {
  const folder = resolve(folderPath);
  const server = createServer((request, response) => {
    const isPicks = request.method === "POST" && request.url.split("?")[0].endsWith("/picks");
    const isRead = request.method === "GET" || request.method === "HEAD";
    const handled = isPicks
      ? savePicks(folder, request, response)
      : isRead
        ? sendFile(folder, request, response)
        : Promise.resolve(response.writeHead(405).end());
    handled.catch(() => response.writeHead(500).end());
  });
  return new Promise((ready) => server.listen(port, "127.0.0.1", () => ready(server)));
}

export function waitForPicks(folderPath, pollMs = 500) {
  const file = join(resolve(folderPath), PICKS_FILE);
  const taken = file + ".taken";
  const takePicks = async () => {
    const isTaken = await rename(file, taken).then(() => true, () => false);
    if (!isTaken) return null;
    const picks = await readFile(taken, "utf8");
    await rm(taken);
    return picks.trim();
  };
  return new Promise((done, failed) => {
    const check = () =>
      takePicks().then((picks) => {
        if (picks === null) return;
        unwatchFile(file, check);
        done(picks);
      }, failed);
    watchFile(file, { interval: pollMs }, check);
    check();
  });
}

const USAGE = "Usage: sketch.mjs serve <folder> <port> | sketch.mjs wait <folder>";

async function main([command, folder, port]) {
  if (command === "serve" && folder && Number(port) > 0) {
    await serve(folder, Number(port));
    console.log(`Serving ${resolve(folder)} on http://127.0.0.1:${port}/`);
  } else if (command === "wait" && folder) {
    console.log(await waitForPicks(folder));
  } else {
    console.error(USAGE);
    process.exitCode = 2;
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await main(process.argv.slice(2));
}
