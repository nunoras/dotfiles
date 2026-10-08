#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { addWatched, readWatched, watchCommand, watcherAlive } from "./agni-watch-lib.mjs";

const TASK_ID = /^t-\d+$/;
const ARM_GRACE_MS = 3000;

function readInput() {
  try {
    return JSON.parse(readFileSync(0, "utf8"));
  } catch {
    return {};
  }
}

function tasksFromShell(command) {
  const tasks = [];
  for (const match of command.matchAll(/\bagni\s+project\s+(?:approve|retry)\b([^;&|\n]*)/g)) {
    const words = match[1].trim().split(/\s+/);
    const projectIndex = words.indexOf("--project");
    const project = projectIndex === -1 ? null : (words[projectIndex + 1] ?? "").replace(/^["']|["']$/g, "");
    for (const word of words) {
      if (TASK_ID.test(word)) {
        tasks.push({ project, id: word });
      }
    }
  }
  return tasks;
}

function tasksFromTool(toolName, input) {
  if (/agni_approve$/.test(toolName)) {
    return (input.tasks ?? []).map((id) => ({ project: input.project ?? null, id }));
  }
  if (/agni_retry$/.test(toolName)) {
    return input.task ? [{ project: input.project ?? null, id: input.task }] : [];
  }
  return tasksFromShell(String(input.command ?? ""));
}

function armInstruction(sessionId) {
  return [
    `Arm the agni watcher now: run \`${watchCommand(sessionId)}\` as a background shell command.`,
    "Each time it returns, post its lines verbatim except the final `watch:` line, with nothing added.",
    "If the `watch:` line says rearm, start it again in the background.",
  ].join(" ");
}

function sleep(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function onPostToolUse(input) {
  const added = tasksFromTool(input.tool_name ?? "", input.tool_input ?? {});
  if (added.length === 0) {
    return;
  }
  addWatched(input.session_id, added);
  if (watcherAlive(input.session_id)) {
    return;
  }
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: armInstruction(input.session_id) },
    }),
  );
}

function onStop(input) {
  if (input.stop_hook_active || readWatched(input.session_id).length === 0) {
    return;
  }
  const deadline = Date.now() + ARM_GRACE_MS;
  while (!watcherAlive(input.session_id) && Date.now() < deadline) {
    sleep(200);
  }
  if (watcherAlive(input.session_id)) {
    return;
  }
  process.stdout.write(JSON.stringify({ decision: "block", reason: armInstruction(input.session_id) }));
}

const input = readInput();
if (input.session_id) {
  if (input.hook_event_name === "PostToolUse") {
    onPostToolUse(input);
  } else if (input.hook_event_name === "Stop") {
    onStop(input);
  }
}
