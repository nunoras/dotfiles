#!/usr/bin/env node
// skill-improver Stop hook: the "auto-loop" trigger.
//
// On every Stop it inspects the session transcript, counts Skill invocations
// (excluding skill-improver itself), and keeps a per-session marker. When a NEW
// skill on the allowlist has been used since the last check, it blocks the stop
// once and asks the model to run a silent skill-improver self-review. Normal
// turns - and turns that only used non-allowlisted skills - stop instantly.
//
// Cost control: only the skills listed in skill-improver-skills.json (or the
// SKILL_IMPROVER_SKILLS env var, comma-separated) trigger a review. An empty
// allowlist reviews nothing; a missing/unparseable config reviews everything.
//
// Safety: honors stop_hook_active (no recursion), advances the marker before
// blocking, and fails open on any error so it can never wedge a session.
// Disable entirely with env SKILL_IMPROVER_LOOP=0.

import { readFileSync, mkdirSync, writeFileSync, existsSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const SELF = "skill-improver";

function allowStop() {
  // No output + exit 0 => let the agent stop normally.
  process.exit(0);
}

function blockStop(reason) {
  process.stdout.write(JSON.stringify({ decision: "block", reason }));
  process.exit(0);
}

// Returns a Set of skill names to review, or null = "no allowlist configured"
// (review every skill). An empty Set means "review nothing".
function loadAllowlist() {
  const env = process.env.SKILL_IMPROVER_SKILLS;
  if (typeof env === "string" && env.trim()) {
    return new Set(env.split(",").map((s) => s.trim()).filter(Boolean));
  }
  try {
    const here = dirname(fileURLToPath(import.meta.url));
    const cfg = JSON.parse(readFileSync(join(here, "skill-improver-skills.json"), "utf8"));
    if (Array.isArray(cfg.skills)) {
      return new Set(cfg.skills.map((s) => String(s).trim()).filter(Boolean));
    }
  } catch {
    // no config / unreadable => inactive (review all)
  }
  return null;
}

try {
  if (process.env.SKILL_IMPROVER_LOOP === "0") allowStop();

  const raw = readFileSync(0, "utf8"); // stdin
  const input = JSON.parse(raw);

  // Already inside a stop-hook continuation -> never recurse.
  if (input.stop_hook_active) allowStop();

  const transcriptPath = input.transcript_path;
  const sessionId = input.session_id || "unknown";
  if (!transcriptPath || !existsSync(transcriptPath)) allowStop();

  // Collect, in order, every Skill invocation that is not skill-improver.
  const skills = [];
  const lines = readFileSync(transcriptPath, "utf8").split("\n");
  for (const line of lines) {
    if (!line || line.indexOf('"Skill"') === -1) continue;
    let evt;
    try {
      evt = JSON.parse(line);
    } catch {
      continue;
    }
    const content = evt?.message?.content;
    if (!Array.isArray(content)) continue;
    for (const block of content) {
      if (block?.type === "tool_use" && block?.name === "Skill") {
        const name = block?.input?.skill;
        if (typeof name === "string" && name && name !== SELF) {
          skills.push(name);
        }
      }
    }
  }

  // Per-session marker: how many qualifying skill calls we have already seen.
  const markerDir = join(homedir(), ".claude", ".cache", "skill-improver", "markers");
  const markerFile = join(markerDir, `${sessionId}.json`);
  let lastCount = 0;
  try {
    if (existsSync(markerFile)) {
      lastCount = JSON.parse(readFileSync(markerFile, "utf8")).lastCount ?? 0;
    }
  } catch {
    lastCount = 0;
  }

  const newOnes = skills.slice(lastCount);
  if (newOnes.length === 0) allowStop();

  // Advance the marker BEFORE blocking so the forced continuation can't
  // re-trigger, and so non-allowlisted skills are marked seen and never
  // re-scanned next turn.
  try {
    mkdirSync(markerDir, { recursive: true });
    writeFileSync(markerFile, JSON.stringify({ lastCount: skills.length }));
  } catch {
    // If we can't persist the marker, don't risk a loop: just allow the stop.
    allowStop();
  }

  // Restrict to the skills you actually iterate on. null => review everything.
  const allow = loadAllowlist();
  const toReview = allow ? newOnes.filter((s) => allow.has(s)) : newOnes;
  if (toReview.length === 0) allowStop();

  const used = [...new Set(toReview)].join(", ");
  const reason = [
    `AUTO IMPROVEMENT CHECK (skill-improver loop).`,
    `New skill usage this session since the last check: ${used}.`,
    ``,
    `Before stopping, run the skill-improver self-review for the skill(s) above against THIS conversation:`,
    `1. Read ~/.claude/skills/skill-improver/CHANGELOG.md first; do not re-propose anything already applied or rejected.`,
    `2. Apply skill-improver's threshold: only surface a change if the user had to correct/repeat/clarify, explicitly asked, a gap recurred, or it affects safety/privacy/accuracy.`,
    `3. If nothing clears the bar, output exactly one short line: "skill-improver: no actionable improvements for ${used}" and then stop.`,
    `4. If something clears the bar, produce the skill-improver review (exact diff against the real SKILL.md) and ASK before applying. Never modify a skill without explicit user approval.`,
  ].join("\n");

  blockStop(reason);
} catch {
  // Fail open: never block a stop because of a hook error.
  allowStop();
}
