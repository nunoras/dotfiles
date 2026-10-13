import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { decide } from "./pkill-guard.mjs";

const denied = (command) => decide({ tool_input: { command } })?.hookSpecificOutput.permissionDecision === "deny";

test("denies the commands that killed their own shell last week", () => {
  for (const command of [
    "pkill -f cors_serve.py; rm -f sender.html",
    'pkill -f "http.server 8765"; echo stopped',
    "cd /tmp/x && pkill -9 -f /tmp/vf/serve.py",
    'pgrep -f "agni-watch.mjs --session 5b47deb7" | xargs -r kill; echo done',
    "kill $(pgrep -f 'user-data-dir=/tmp/chromium-gh-copy' | head -1) 2>/dev/null",
    "pkill --full vite",
    "pkill -fx 'node server.js'",
  ]) assert.ok(denied(command), command);
});

test("allows commands that cannot match their own shell", () => {
  for (const command of [
    "pkill vite",
    "pkill -x python3",
    "pkill -f '[c]ors_serve.py'",
    "pgrep -f vite",
    "pkill -u nunoras -f '[v]ite'",
    "fuser -k 8765/tcp",
    "echo pkill -f is risky",
  ]) assert.ok(!denied(command), command);
});

test("bracket form is still denied when the plain name appears elsewhere", () => {
  assert.ok(denied("bash -c 'exec -a zzqq_victim sleep 300' & pkill -f '[z]zqq_victim'"));
});

test("hook process prints a deny for stdin input", () => {
  const script = fileURLToPath(new URL("./pkill-guard.mjs", import.meta.url));
  const run = spawnSync("node", [script], { input: JSON.stringify({ tool_input: { command: "pkill -f foo" } }), encoding: "utf8" });
  assert.equal(JSON.parse(run.stdout).hookSpecificOutput.permissionDecision, "deny");
  const quiet = spawnSync("node", [script], { input: JSON.stringify({ tool_input: { command: "ls" } }), encoding: "utf8" });
  assert.equal(quiet.stdout, "");
});
