#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import {
  FINISHED_STATES,
  isFinished,
  claimWatcher,
  matches,
  overviewOn,
  parseTable,
  readWatched,
  releaseWatcher,
  watchCommand,
  writeWatched,
} from "./agni-watch-lib.mjs";
import { pullRequestNumber, render } from "./agni-watch-render.mjs";
import { overviewFingerprint, projectAt } from "./agni-overview-render.mjs";

const INTERVAL_SECONDS = Number(process.env.AGNI_WATCH_INTERVAL ?? 600);
const RETRY_SECONDS = 15;
const ATTENTION_STATES = new Set([...FINISHED_STATES, "waiting_on_question"]);

function agniStatus(waitSeconds) {
  const args = waitSeconds > 0 ? ["status", "--wait", String(waitSeconds)] : ["status"];
  const result = spawnSync("agni", args, { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  if (result.status !== 0) {
    return null;
  }
  return { tasks: parseTable(result.stdout, "tasks"), projects: parseTable(result.stdout, "projects") };
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

function clock() {
  return new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", hour12: false });
}

function pullRequest(row, projects) {
  const number = pullRequestNumber(row);
  if (!number && !row.branch) {
    return null;
  }
  const cwd = projects.find((project) => project.name === row.project)?.path;
  const args = number
    ? ["pr", "view", number, "--json", "number,url"]
    : ["pr", "list", "--head", row.branch, "--json", "number,url", "-q", ".[0]"];
  const result = spawnSync("gh", args, { cwd, encoding: "utf8" });
  if (result.status !== 0 || !result.stdout.trim()) {
    return null;
  }
  return JSON.parse(result.stdout);
}

function t3Actions(lines, projects) {
  const actions = [];
  for (const { task, row } of lines) {
    if (!row) {
      continue;
    }
    if (!task.linkedPr) {
      const found = pullRequest(row, projects);
      if (found) {
        actions.push(`link ${found.url}`, `watch ${found.url}`);
        task.linkedPr = String(found.number);
      }
    }
    if (isFinished(row)) {
      actions.push(`card ${row.project} ${row.id}`);
    }
  }
  return actions;
}

function overviewRows(overview, status, watched) {
  const unwatched = status.tasks.filter((row) => !watched.some((task) => matches(row, task)));
  if (overview?.scope !== "here") {
    return unwatched;
  }
  const project = projectAt(status.projects, overview.cwd);
  return unwatched.filter((row) => row.project === project);
}

function overviewAction(overview) {
  return overview.scope === "here" ? "overview --here" : "overview";
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
  if (watched.length === 0 && overviewOn(sessionId) === null) {
    console.log(`${clock()}  no agni tasks watched`);
    return;
  }

  claimWatcher(sessionId);
  try {
    const deadline = Date.now() + INTERVAL_SECONDS * 1000;
    let status = agniStatus(0) ?? { tasks: [], projects: [] };
    let rows = status.tasks;
    const before = fingerprint(rows, watched);
    const overviewBefore = overviewFingerprint(overviewRows(overviewOn(sessionId), status, watched));
    let overviewChanged = false;
    for (let remaining = INTERVAL_SECONDS; remaining > 0; remaining = Math.ceil((deadline - Date.now()) / 1000)) {
      const latest = agniStatus(remaining);
      if (!latest) {
        pause(Math.min(remaining, RETRY_SECONDS));
        continue;
      }
      status = latest;
      rows = latest.tasks;
      const overview = overviewOn(sessionId);
      overviewChanged = overview !== null && overviewFingerprint(overviewRows(overview, status, watched)) !== overviewBefore;
      if (overviewChanged || (fingerprint(rows, watched) !== before && needsAttention(rows, watched))) {
        break;
      }
    }

    const lines = tracked(rows, watched);
    const actions = t3Actions(lines, status.projects);
    if (overviewChanged) {
      actions.push(overviewAction(overviewOn(sessionId)));
    }
    if (watched.length > 0) {
      console.log(render({ time: clock(), tracked: lines, actions }));
    } else if (actions.length > 0) {
      console.log(actions.map((action) => `t3: ${action}`).join("\n"));
    }
    const open = lines.filter(({ row }) => row && !isFinished(row)).map(({ task }) => task);
    writeWatched(sessionId, open);
    const keepWatching = open.length > 0 || overviewOn(sessionId) !== null;
    console.log(keepWatching ? `watch: rearm with ${watchCommand(sessionId)}` : "watch: all finished, do not rearm");
  } finally {
    releaseWatcher(sessionId);
  }
}

main();
