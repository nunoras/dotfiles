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
const TITLE_WIDTH = 32;
const RETRY_SECONDS = 15;
const PLAIN_STATES = {
  proposed: "not approved",
  approved: "queued",
  running: "building",
  reviewing: "in review",
  validating: "testing",
  waiting_on_question: "needs your answer",
  pr_open: "PR open",
  landed: "merged",
  validated: "approved",
  done: "done",
  failed: "failed",
  cancelled: "cancelled",
  canceled: "cancelled",
};
const NEEDS_YOU_STATES = new Set(["waiting_on_question", "pr_open", "failed", "proposed"]);
const GROUPS = ["Needs you", "Working", "Done"];
const GROUP_LABEL_WIDTH = Math.max(...GROUPS.map((group) => group.length)) + 2;
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

function shortTitle(title) {
  return clip(title.split(/,|;| with | so | because /)[0].trim(), TITLE_WIDTH);
}

function plainState(state) {
  return PLAIN_STATES[state] ?? state.replaceAll("_", " ");
}

function blockedOnPerson(row) {
  return row.waitsOn?.startsWith("a person") && !NEEDS_YOU_STATES.has(row.state);
}

function groupOf({ row }) {
  if (!row || NEEDS_YOU_STATES.has(row.state) || blockedOnPerson(row)) {
    return "Needs you";
  }
  return FINISHED_STATES.has(row.state) ? "Done" : "Working";
}

function describe({ task, row }) {
  if (!row) {
    return `${task.id}  (not found)`;
  }
  const status = blockedOnPerson(row) ? `${plainState(row.state)}, stuck` : plainState(row.state);
  return `${row.id}  ${shortTitle(row.title)}  (${status})`;
}

function report(lines) {
  const out = [];
  for (const group of GROUPS) {
    const members = lines.filter((line) => groupOf(line) === group).map(describe);
    const entries = members.length > 0 ? members : ["none"];
    entries.forEach((entry, index) => {
      const label = index === 0 ? `${group}:` : "";
      out.push(`${label.padEnd(GROUP_LABEL_WIDTH)} ${entry}`);
    });
  }
  return out;
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
    for (const line of report(lines)) {
      console.log(line);
    }
    const open = lines.filter(({ row }) => row && !FINISHED_STATES.has(row.state)).map(({ task }) => task);
    writeWatched(sessionId, open);
    console.log(open.length === 0 ? "watch: all finished, do not rearm" : `watch: rearm with ${watchCommand(sessionId)}`);
  } finally {
    releaseWatcher(sessionId);
  }
}

main();
