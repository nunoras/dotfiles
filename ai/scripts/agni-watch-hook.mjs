#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { addWatched, hasWatchWork, overviewToggle, setOverview, watchCommand, watcherAlive } from "./agni-watch-lib.mjs";

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
  for (const match of command.matchAll(/(?:^|[;&|(])\s*agni\s+project\s+(?:approve|retry)\b([^;&|\n`]*)/gm)) {
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
    "Each time it returns, post its lines verbatim as Markdown, except the `t3:` lines and the final `watch:` line, with nothing added.",
    "Act on each `t3:` line when T3 Code tools are available, and skip them otherwise:",
    "`t3: title <text>` renames this thread with t3_thread_update; `t3: link <url>` calls link_pull_request; `t3: watch <url>` calls watch_pull_request;",
    "`t3: card <project> <task>` renders a status card for the finished task with html_render, built from the rows of `agni status --task <task>` that belong to that project (rounds, review verdicts, validations, the PR, and any proof video);",
    '`t3: overview [flags]` runs `node "$HOME/.claude/scripts/agni-overview.mjs" [flags]` from the project directory and passes its stdout unchanged to html_render with title `agni overview` and height 2000.',
    "If the `watch:` line says rearm, start it again in the background.",
  ].join(" ");
}

function sleep(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function overviewFor(toggle, cwd) {
  if (toggle === "off") {
    return null;
  }
  return toggle === "here" ? { scope: "here", cwd: cwd ?? process.cwd() } : { scope: "all" };
}

function onPostToolUse(input) {
  const added = tasksFromTool(input.tool_name ?? "", input.tool_input ?? {});
  const toggle = overviewToggle(String(input.tool_input?.command ?? ""));
  if (toggle) {
    setOverview(input.session_id, overviewFor(toggle, input.cwd));
  }
  if (added.length === 0 && (!toggle || toggle === "off")) {
    return;
  }
  if (added.length > 0) {
    addWatched(input.session_id, added);
  }
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
  if (input.stop_hook_active || !hasWatchWork(input.session_id)) {
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
