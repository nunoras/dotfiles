import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export const FINISHED_STATES = new Set(["landed", "done", "validated", "pr_open", "failed", "cancelled", "canceled"]);

export function isFinished(row) {
  if (row.state === "validated") {
    return !row.waitsOn || row.waitsOn.startsWith("nothing");
  }
  return FINISHED_STATES.has(row.state);
}

const STATE_DIR = join(homedir(), ".claude", "agni-watch");

export function watchCommand(sessionId) {
  return `node "$HOME/.claude/scripts/agni-watch.mjs" --session ${sessionId}`;
}

function statePath(sessionId) {
  return join(STATE_DIR, `${sessionId}.json`);
}

function pidPath(sessionId) {
  return join(STATE_DIR, `${sessionId}.pid`);
}

function readState(sessionId) {
  try {
    const state = JSON.parse(readFileSync(statePath(sessionId), "utf8"));
    return { tasks: state.tasks ?? [], overview: state.overview?.scope ? state.overview : null };
  } catch {
    return { tasks: [], overview: null };
  }
}

function writeState(sessionId, state) {
  if (state.tasks.length === 0 && !state.overview) {
    rmSync(statePath(sessionId), { force: true });
    return;
  }
  mkdirSync(STATE_DIR, { recursive: true });
  writeFileSync(statePath(sessionId), `${JSON.stringify(state, null, 2)}\n`);
}

export function readWatched(sessionId) {
  return readState(sessionId).tasks;
}

export function writeWatched(sessionId, tasks) {
  writeState(sessionId, { ...readState(sessionId), tasks });
}

export function overviewOn(sessionId) {
  return readState(sessionId).overview;
}

export function setOverview(sessionId, overview) {
  writeState(sessionId, { ...readState(sessionId), overview });
}

export function hasWatchWork(sessionId) {
  const state = readState(sessionId);
  return state.overview !== null || state.tasks.length > 0;
}

export function overviewToggle(command) {
  const match = command.match(/(?:^|[;&|(])\s*node\s+"?[^\s;&|"]*agni-overview\.mjs"?([^;&|\n]*)/m);
  if (!match) {
    return null;
  }
  if (/(^|\s)--off\b/.test(match[1])) {
    return "off";
  }
  return /(^|\s)--here\b/.test(match[1]) ? "here" : "all";
}

export function addWatched(sessionId, added) {
  const tasks = readWatched(sessionId);
  for (const task of added) {
    if (!tasks.some((known) => known.id === task.id && known.project === task.project)) {
      tasks.push(task);
    }
  }
  writeWatched(sessionId, tasks);
  return tasks;
}

export function claimWatcher(sessionId) {
  mkdirSync(STATE_DIR, { recursive: true });
  writeFileSync(pidPath(sessionId), String(process.pid));
}

export function releaseWatcher(sessionId) {
  try {
    if (readFileSync(pidPath(sessionId), "utf8").trim() === String(process.pid)) {
      rmSync(pidPath(sessionId), { force: true });
    }
  } catch {}
}

export function watcherAlive(sessionId) {
  let pid;
  try {
    pid = Number(readFileSync(pidPath(sessionId), "utf8").trim());
  } catch {
    return false;
  }
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error.code === "EPERM";
  }
}

function splitRow(row) {
  const fields = [];
  let field = "";
  let quoted = false;
  for (let i = 0; i < row.length; i += 1) {
    const char = row[i];
    if (quoted) {
      if (char === "\\" && i + 1 < row.length) {
        const next = row[++i];
        field += next === "n" ? "\n" : next === "t" ? "\t" : next;
      } else if (char === '"') {
        quoted = false;
      } else {
        field += char;
      }
    } else if (char === '"') {
      quoted = true;
    } else if (char === ",") {
      fields.push(field);
      field = "";
    } else {
      field += char;
    }
  }
  fields.push(field);
  return fields;
}

export function parseTasks(toon) {
  return parseTable(toon, "tasks");
}

export function parseTable(toon, name) {
  const lines = toon.split(/\r?\n/);
  const start = lines.findIndex((line) => line.startsWith(`${name}[`) && /^\w+\[\d+\]\{/.test(line));
  if (start === -1) {
    return [];
  }
  const columns = lines[start].slice(lines[start].indexOf("{") + 1, lines[start].indexOf("}")).split(",");
  const tasks = [];
  for (const line of lines.slice(start + 1)) {
    if (!line.startsWith("  ")) {
      break;
    }
    const fields = splitRow(line.trim());
    tasks.push(Object.fromEntries(columns.map((column, index) => [column, fields[index] ?? ""])));
  }
  return tasks;
}

export function matches(row, task) {
  return row.id === task.id && (!task.project || row.project === task.project);
}
