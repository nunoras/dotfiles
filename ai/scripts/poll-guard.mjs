#!/usr/bin/env node
import { readFileSync, realpathSync } from "node:fs";
import { pathToFileURL } from "node:url";

const HEREDOC = /<<-?\s*['"]?(\w+)['"]?[\s\S]*?\n\1\b/g;
const POLL_LOOP =
  /(^|[;&|({]\s*|\bdo\s+|\n\s*)(until|while|for)\b[^\n]*?[;\n]\s*do\b[\s\S]*?\b(sleep|Start-Sleep)\b|\bwhile\s*\([\s\S]*?\bStart-Sleep\b/i;
const LONG_SLEEP = /\b(sleep|Start-Sleep(\s+-Seconds)?)\s+(\d+)/g;

export function verdict(input) {
  const command = input?.tool_input?.command;
  if (typeof command !== "string" || input.tool_input.run_in_background) return null;
  const executed = command.replace(HEREDOC, "");
  const longest = Math.max(0, ...[...executed.matchAll(LONG_SLEEP)].map((match) => Number(match[3])));
  if (longest >= 5 && POLL_LOOP.test(executed)) return "a foreground poll loop";
  return longest >= 30 ? `a foreground sleep of ${longest}s` : null;
}

function readStdin() {
  try {
    return JSON.parse(readFileSync(0, "utf8"));
  } catch {
    return null;
  }
}

function main() {
  const reason = verdict(readStdin());
  if (!reason) return;
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: `Blocked ${reason}. Start the long command with run_in_background: true and end the turn; you are re-invoked when it exits. To wait on a file, log line or external status, use the Monitor tool with an until-condition.`,
      },
    }),
  );
}

if (import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href) main();
