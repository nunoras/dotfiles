#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync, realpathSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const CONFIG_PATH = join(homedir(), ".claude", "verify-gate.json");
const STATE_PATH = join(homedir(), ".claude", "verify-gate-state.json");
const MAX_BLOCKS_PER_SESSION = 3;
const RUN_TIMEOUT_MS = 540_000;
const OUTPUT_TAIL_LINES = 40;

function readJson(path, fallback) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return fallback;
  }
}

function writeJson(path, value) {
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`);
}

function git(cwd, args) {
  const result = spawnSync("git", args, { cwd, encoding: "buffer", maxBuffer: 256 * 1024 * 1024 });
  return result.status === 0 ? result.stdout : null;
}

function repoRoot(cwd) {
  const output = git(cwd, ["rev-parse", "--show-toplevel"]);
  return output ? realpathSync(output.toString().trim()) : null;
}

function treeFingerprint(root) {
  const hash = createHash("sha256");
  hash.update(git(root, ["rev-parse", "HEAD"]) ?? "no-head");
  hash.update(git(root, ["diff", "HEAD", "--binary"]) ?? "");
  const untracked = (git(root, ["ls-files", "--others", "--exclude-standard", "-z"]) ?? Buffer.alloc(0))
    .toString()
    .split("\0")
    .filter(Boolean);
  for (const path of untracked) {
    hash.update(path);
    try {
      hash.update(readFileSync(join(root, path)));
    } catch {
      hash.update("unreadable");
    }
  }
  return hash.digest("hex");
}

function tail(text) {
  return text.split(/\r?\n/).slice(-OUTPUT_TAIL_LINES).join("\n");
}

function configure(argv) {
  const root = repoRoot(process.cwd());
  if (!root) {
    console.error("verify-gate: run this inside a git repository");
    process.exit(1);
  }
  const config = readJson(CONFIG_PATH, {});
  if (argv[0] === "--set" && argv[1]) config[root] = argv[1];
  else if (argv[0] === "--unset") delete config[root];
  else if (argv[0] !== "--list") {
    console.error('usage: verify-gate.mjs --set "<command>" | --unset | --list');
    process.exit(1);
  }
  if (argv[0] !== "--list") writeJson(CONFIG_PATH, config);
  console.log(JSON.stringify(config, null, 2));
}

function gate(input) {
  const root = repoRoot(input.cwd ?? process.cwd());
  const command = root && readJson(CONFIG_PATH, {})[root];
  if (!command) return;

  const state = readJson(STATE_PATH, { passed: {}, blocks: {} });
  const fingerprint = treeFingerprint(root);
  if (state.passed[root] === fingerprint) return;

  const run = spawnSync(command, { cwd: root, shell: true, encoding: "utf8", timeout: RUN_TIMEOUT_MS, maxBuffer: 64 * 1024 * 1024 });
  const sessionKey = input.session_id ?? "unknown";

  if (run.status === 0) {
    state.passed[root] = fingerprint;
    delete state.blocks[sessionKey];
    writeJson(STATE_PATH, state);
    return;
  }

  const blocks = (state.blocks[sessionKey] ?? 0) + 1;
  state.blocks[sessionKey] = blocks;
  writeJson(STATE_PATH, state);

  const outcome = run.error ? String(run.error.message) : `exit ${run.status}`;
  const output = tail(`${run.stdout ?? ""}\n${run.stderr ?? ""}`.trim());

  if (blocks > MAX_BLOCKS_PER_SESSION) {
    process.stdout.write(
      JSON.stringify({
        systemMessage: `verify-gate: \`${command}\` still fails (${outcome}) after ${MAX_BLOCKS_PER_SESSION} attempts. Report the turn as BLOCKED, not DONE.`,
      }),
    );
    return;
  }

  console.error(
    [
      `verify-gate: \`${command}\` failed (${outcome}) on the current working tree, attempt ${blocks} of ${MAX_BLOCKS_PER_SESSION}.`,
      "Fix the cause and let the turn end again. Do not report DONE while this fails.",
      "",
      output,
    ].join("\n"),
  );
  process.exit(2);
}

const argv = process.argv.slice(2);
if (argv.length > 0) configure(argv);
else gate(readJson(0, {}));
