import { test } from "node:test";
import assert from "node:assert/strict";
import { access, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { serve, waitForPicks } from "./sketch.mjs";

async function serveBoard(t) {
  const folder = await mkdtemp(join(tmpdir(), "sketch-"));
  await writeFile(join(folder, "index.html"), "<p>first</p>");
  const server = await serve(folder, 0);
  t.after(() => server.close());
  return { folder, url: `http://127.0.0.1:${server.address().port}` };
}

const sendPicks = (url, picks) => fetch(`${url}/picks`, { method: "POST", body: picks });

test("serves the board with a version that changes when the file changes", async (t) => {
  const { folder, url } = await serveBoard(t);
  const first = await fetch(`${url}/`);
  assert.equal(await first.text(), "<p>first</p>");
  assert.match(first.headers.get("content-type"), /text\/html/);

  await writeFile(join(folder, "index.html"), "<p>second, edited</p>");
  const second = await fetch(`${url}/`, { method: "HEAD" });
  assert.notEqual(second.headers.get("etag"), first.headers.get("etag"));
});

test("picks the user sends reach the agent that waits for them", async (t) => {
  const { folder, url } = await serveBoard(t);
  const waiting = waitForPicks(folder, 20);
  const response = await sendPicks(url, "Locked: O1-B. Leaning: O2-A.");
  assert.equal(response.status, 204);
  assert.equal(await waiting, "Locked: O1-B. Leaning: O2-A.");
});

test("picks sent before the wait starts are delivered once", async (t) => {
  const { folder, url } = await serveBoard(t);
  await sendPicks(url, "Locked: O1-A. Leaning: none.");
  assert.equal(await waitForPicks(folder, 20), "Locked: O1-A. Leaning: none.");
  await assert.rejects(access(join(folder, "picks.txt")));
});

test("refuses empty picks and files outside the folder", async (t) => {
  const { url } = await serveBoard(t);
  assert.equal((await sendPicks(url, "")).status, 400);
  assert.equal((await fetch(`${url}/..%2fsecret.txt`)).status, 403);
  assert.equal((await fetch(`${url}/missing.html`)).status, 404);
});
