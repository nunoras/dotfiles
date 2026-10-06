#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { isAbsolute, resolve } from "node:path";

const PUBLISHING_COMMAND =
  /\b(gh\s+(pr|issue)\s+(create|edit|comment|review)|git\s+commit|agni\s+(project\s+(propose|answer)|worker\s+(submit|ask)))\b/;
const FILE_FLAGS = new Set(["--body-file", "-F", "--file", "--description"]);
const EM_DASH = "\u2014";
const EMOJI = /(?![\u00A9\u00AE\u2122])\p{Extended_Pictographic}/u;

function readStdin() {
  try {
    return JSON.parse(readFileSync(0, "utf8"));
  } catch {
    return null;
  }
}

function tokenize(command) {
  return [...command.matchAll(/"((?:\\.|[^"\\])*)"|'([^']*)'|(\S+)/g)].map(
    (match) => match[1] ?? match[2] ?? match[3],
  );
}

function windowsPath(posixPath) {
  const result = spawnSync("cygpath", ["-w", posixPath], { encoding: "utf8" });
  return result.status === 0 ? result.stdout.trim() : posixPath;
}

function resolveFile(token, cwd) {
  const path = isAbsolute(token) ? token : resolve(cwd, token);
  if (existsSync(path) || process.platform !== "win32" || !token.startsWith("/")) return path;
  return windowsPath(token);
}

function referencedFiles(command, cwd) {
  const tokens = tokenize(command);
  const files = [];
  for (let index = 0; index < tokens.length - 1; index++) {
    if (!FILE_FLAGS.has(tokens[index])) continue;
    const path = resolveFile(tokens[index + 1], cwd);
    if (existsSync(path)) files.push(path);
  }
  return files;
}

function offences(source, text) {
  return text.split(/\r?\n/).flatMap((line, index) => {
    const found = [];
    if (line.includes(EM_DASH)) found.push("em dash");
    const emoji = line.match(EMOJI);
    if (emoji) found.push(`emoji ${emoji[0]}`);
    return found.length ? [`${source}:${index + 1}: ${found.join(", ")}: ${line.trim().slice(0, 120)}`] : [];
  });
}

const input = readStdin();
const command = input?.tool_input?.command;
if (typeof command !== "string" || !PUBLISHING_COMMAND.test(command)) process.exit(0);

const cwd = input.cwd ?? process.cwd();
const problems = [
  ...offences("command", command),
  ...referencedFiles(command, cwd).flatMap((path) => {
    try {
      return offences(path, readFileSync(path, "utf8"));
    } catch {
      return [];
    }
  }),
];
if (problems.length === 0) process.exit(0);

process.stdout.write(
  JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: [
        "Published text must not contain emojis or em dashes. Rewrite these lines with plain words, commas or full stops, then run the command again:",
        ...problems,
      ].join("\n"),
    },
  }),
);
