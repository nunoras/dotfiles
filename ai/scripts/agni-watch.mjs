#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import {
  FINISHED_STATES,
  claimWatcher,
  matches,
  parseTasks,
  readWatched,
  releaseWatcher,
  watchCommand,
  writeWatched,
} from "./agni-watch-lib.mjs";

const INTERVAL_SECONDS = Number(process.env.AGNI_WATCH_INTERVAL ?? 600);
const TITLE_WIDTH = 40;
const WAITS_WIDTH = 80;
const RETRY_SECONDS = 15;
const ATTENTION_STATES = new Set([...FINISHED_STATES, "waiting_on_question"]);

function agniStatus(waitSeconds) {
  const args = waitSeconds > 0 ? ["status", "--wait", String(waitSeconds)] : ["status"];
  const result = spawnSync("agni", args, { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  return result.status === 0 ? parseTasks(result.stdout) : null;
}

function pause(seconds) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, seconds * 1000);
}

function tracked(rows, watched) {
  return watched.map((task) => ({ task, row: rows.find((row) => matches(row, task)) }));
}

function fingerprint(rows, watched) {
  return tracked(rows, watched)
    .map(({ row }) => (row ? `${row.state}|${row.round}|${row.waitsOn}` : "missing"))
    .join("\n");
}

function needsAttention(rows, watched) {
  return tracked(rows, watched).some(({ row }) => !row || ATTENTION_STATES.has(row.state));
}

function clip(text, width) {
  return text.length > width ? `${text.slice(0, width - 1)}…` : text;
}

function clock() {
  return new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", hour12: false });
}

function describe({ task, row }) {
  if (!row) {
    return `${task.id}  not found`;
  }
  const round = Number(row.round) > 0 ? ` r${row.round}` : "";
  const waits = row.waitsOn && row.waitsOn !== "nothing" ? `  waits: ${clip(row.waitsOn, WAITS_WIDTH)}` : "";
  return `${row.project} ${row.id}  ${clip(row.title, TITLE_WIDTH)}  ${row.state}${round}${waits}`;
}

function sessionArg() {
  const index = process.argv.indexOf("--session");
  return index === -1 ? null : process.argv[index + 1];
}

function main() {
  const sessionId = sessionArg();
  if (!sessionId) {
    console.error("usage: agni-watch.mjs --session <session-id>");
    process.exit(64);
  }
  const watched = readWatched(sessionId);
  if (watched.length === 0) {
    console.log(`${clock()}  no agni tasks watched`);
    return;
  }

  claimWatcher(sessionId);
  try {
    const deadline = Date.now() + INTERVAL_SECONDS * 1000;
    let rows = agniStatus(0) ?? [];
    const before = fingerprint(rows, watched);
    for (let remaining = INTERVAL_SECONDS; remaining > 0; remaining = Math.ceil((deadline - Date.now()) / 1000)) {
      const latest = agniStatus(remaining);
      if (!latest) {
        pause(Math.min(remaining, RETRY_SECONDS));
        continue;
      }
      rows = latest;
      if (fingerprint(rows, watched) !== before && needsAttention(rows, watched)) {
        break;
      }
    }

    const lines = tracked(rows, watched);
    console.log(clock());
    for (const line of lines) {
      console.log(describe(line));
    }
    const open = lines.filter(({ row }) => row && !FINISHED_STATES.has(row.state)).map(({ task }) => task);
    writeWatched(sessionId, open);
    console.log(open.length === 0 ? "watch: all finished, do not rearm" : `watch: rearm with ${watchCommand(sessionId)}`);
  } finally {
    releaseWatcher(sessionId);
  }
}

main();
