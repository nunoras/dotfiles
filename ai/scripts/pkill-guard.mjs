#!/usr/bin/env node
import { readFileSync, realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";

const OPTIONS_WITH_VALUE = new Set([
  "-u", "-U", "-g", "-G", "-P", "-s", "-t", "-F", "--signal", "--euid", "--uid",
  "--pgroup", "--group", "--parent", "--session", "--terminal", "--pidfile", "--ns", "--nslist",
]);

function tokenize(text) {
  return [...text.matchAll(/"((?:\\.|[^"\\])*)"|'([^']*)'|([^\s;&|()`]+)/g)].map(
    (match) => match[1] ?? match[2] ?? match[3],
  );
}

function feedsKill(command, start, end) {
  const pipedToKill = /^[^;&\n]*\|\s*xargs\b[^;&|\n]*\bkill\b/.test(command.slice(end));
  const substitutedIntoKill = /\bkill\s+(?:-\S+\s+)*\$\(\s*$/.test(command.slice(0, start + 1));
  return pipedToKill || substitutedIntoKill;
}

function fullMatchPatterns(command) {
  const patterns = [];
  for (const match of command.matchAll(/(?:^|[;&|(\n`])\s*(?:sudo\s+)?(pkill|pgrep)\s+([^;&|\n)`]*)/g)) {
    const [, tool, rest] = match;
    if (tool === "pgrep" && !feedsKill(command, match.index, match.index + match[0].length)) continue;
    const args = tokenize(rest);
    let full = false;
    let pattern;
    for (let index = 0; index < args.length; index++) {
      const arg = args[index];
      if (arg === "-f" || arg === "--full" || /^-[a-eg-zA-Z]*f[a-zA-Z]*$/.test(arg)) full = true;
      if (OPTIONS_WITH_VALUE.has(arg)) index++;
      else if (!arg.startsWith("-") && pattern === undefined) pattern = arg;
    }
    if (full && pattern !== undefined) patterns.push({ tool, pattern });
  }
  return patterns;
}

function matches(pattern, text) {
  try {
    return new RegExp(pattern).test(text);
  } catch {
    return text.includes(pattern);
  }
}

export function selfKillingPatterns(command) {
  return fullMatchPatterns(command).filter(({ pattern }) => matches(pattern, command));
}

export function decide(input) {
  const command = input?.tool_input?.command;
  if (typeof command !== "string") return null;
  const found = selfKillingPatterns(command);
  if (found.length === 0) return null;
  const listed = found.map(({ tool, pattern }) => `${tool} -f '${pattern}'`).join(", ");
  return {
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: [
        `Blocked: ${listed} matches this Bash call's own shell, because the shell's command line contains the pattern.`,
        "The shell gets killed (exit 144) and nothing after it runs.",
        "Stop the process another way: kill the PID you saved when you started it (`kill \"$(cat /tmp/x.pid)\"`), free its port (`fuser -k 8765/tcp`), or use a pattern that does not appear anywhere in this command.",
      ].join(" "),
    },
  };
}

function main() {
  let input;
  try {
    input = JSON.parse(readFileSync(0, "utf8"));
  } catch {
    return;
  }
  const decision = decide(input);
  if (decision) process.stdout.write(JSON.stringify(decision));
}

if (process.argv[1] && fileURLToPath(import.meta.url) === realpathSync(process.argv[1])) main();
