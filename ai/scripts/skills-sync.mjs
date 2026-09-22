#!/usr/bin/env node
import {
  existsSync,
  lstatSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  readlinkSync,
  realpathSync,
  rmdirSync,
  symlinkSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { basename, join, resolve } from "node:path";

const args = new Set(process.argv.slice(2));
const quiet = args.has("--quiet");
const dryRun = args.has("--dry-run");

const home = homedir();
const claudeHome = join(home, ".claude");
const sharedSkillsDir = join(home, ".agents", "skills");
const manifestPath = join(sharedSkillsDir, ".dotfiles-skills-sync.json");
const isWindows = process.platform === "win32";

const say = (line) => quiet || console.log(line);
const warn = (line) => console.error(line);

function readJson(path, fallback) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return fallback;
  }
}

function skillName(skillDir) {
  const text = readFileSync(join(skillDir, "SKILL.md"), "utf8");
  const frontmatter = text.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  const name = frontmatter?.[1].match(/^name:\s*["']?([^"'\r\n]+?)["']?\s*$/m)?.[1];
  return name ?? basename(skillDir);
}

function skillDirsUnder(root) {
  if (!existsSync(root)) return [];
  const found = [];
  for (const entry of readdirSync(root, { withFileTypes: true })) {
    const path = join(root, entry.name);
    if (!entry.isDirectory() && !entry.isSymbolicLink()) continue;
    if (existsSync(join(path, "SKILL.md"))) found.push(path);
    else if (entry.isDirectory()) found.push(...skillDirsUnder(path));
  }
  return found;
}

function personalSkills() {
  const root = join(claudeHome, "skills");
  if (!existsSync(root)) return [];
  const realRoot = realpathSync(root);
  return readdirSync(realRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && existsSync(join(realRoot, entry.name, "SKILL.md")))
    .map((entry) => ({ linkName: entry.name, path: join(realRoot, entry.name), origin: "personal" }));
}

function pluginSkills() {
  const enabled = readJson(join(claudeHome, "settings.json"), {}).enabledPlugins ?? {};
  const installed = readJson(join(claudeHome, "plugins", "installed_plugins.json"), {}).plugins ?? {};
  const skills = [];
  for (const [pluginId, isEnabled] of Object.entries(enabled)) {
    const installPath = installed[pluginId]?.[0]?.installPath;
    if (!isEnabled || !installPath) continue;
    const plugin = pluginId.split("@")[0];
    for (const path of skillDirsUnder(join(installPath, "skills"))) {
      skills.push({ linkName: `${plugin}-${basename(path)}`, path, origin: plugin });
    }
  }
  return skills;
}

function dedupeByName(skills) {
  const byName = new Map();
  for (const skill of skills) {
    const name = skillName(skill.path);
    const kept = byName.get(name);
    if (kept) say(`  dup    ${skill.origin}:${name} (keeping ${kept.origin}:${name})`);
    else byName.set(name, skill);
  }
  return [...byName.values()];
}

const normalize = (path) => {
  const resolved = resolve(path.replace(/^\\\\\?\\/, ""));
  return isWindows ? resolved.toLowerCase() : resolved;
};

function linkTarget(path) {
  try {
    if (!lstatSync(path).isSymbolicLink()) return null;
    return readlinkSync(path);
  } catch {
    return null;
  }
}

function removeLink(path) {
  if (dryRun) return;
  try {
    unlinkSync(path);
  } catch {
    rmdirSync(path);
  }
}

function createLink(path, target) {
  if (dryRun) return;
  symlinkSync(target, path, isWindows ? "junction" : "dir");
}

const desired = new Map(dedupeByName([...personalSkills(), ...pluginSkills()]).map((s) => [s.linkName, s.path]));
const owned = new Set(readJson(manifestPath, []));

if (!dryRun) mkdirSync(sharedSkillsDir, { recursive: true });

for (const name of owned) {
  const path = join(sharedSkillsDir, name);
  const target = linkTarget(path);
  if (target === null) {
    owned.delete(name);
    continue;
  }
  const wanted = desired.get(name);
  if (!wanted || normalize(target) !== normalize(wanted)) {
    removeLink(path);
    owned.delete(name);
    say(`  unlink ${name}`);
  }
}

let linked = 0;
for (const [name, target] of desired) {
  const path = join(sharedSkillsDir, name);
  if (owned.has(name)) continue;
  if (existsSync(path) || linkTarget(path) !== null) {
    warn(`  skip   ${name}: ${path} exists and was not made by this script`);
    continue;
  }
  createLink(path, target);
  owned.add(name);
  linked += 1;
  say(`  link   ${name} -> ${target}`);
}

if (!dryRun) writeFileSync(manifestPath, JSON.stringify([...owned].sort(), null, 2) + "\n");
say(`${dryRun ? "would sync" : "synced"} ${owned.size} skills into ${sharedSkillsDir} (${linked} new)`);
