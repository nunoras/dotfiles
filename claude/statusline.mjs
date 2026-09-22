#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";

const BAR_WIDTH = 22;
const NEW_CHAT_MARKER_PCT = 20;
const MODEL_RAMP = [60, 67, 73, 74, 80];

const paint = (text, code) => `\x1b[${code}m${text}\x1b[0m`;
const visibleLength = (s) => s.replace(/\x1b\[[0-9;]*m/g, "").length;
const isNumber = (v) => typeof v === "number" && Number.isFinite(v);

function readStdin() {
  return new Promise((resolve) => {
    let raw = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => (raw += chunk));
    process.stdin.on("end", () => resolve(raw));
  });
}

function parseStatus(raw) {
  const brace = raw.indexOf("{");
  try {
    return JSON.parse(brace > 0 ? raw.slice(brace) : raw);
  } catch {
    return {};
  }
}

function contextBar(usedPct) {
  if (!isNumber(usedPct)) return { bar: "", label: "" };
  const clamped = Math.max(0, Math.min(100, usedPct));
  const filled = Math.round((clamped / 100) * BAR_WIDTH);
  const markerIdx = Math.round((NEW_CHAT_MARKER_PCT / 100) * BAR_WIDTH);
  const past = clamped >= NEW_CHAT_MARKER_PCT;
  const fillColor = past ? "38;5;215" : "38;5;114";
  const markerColor = past ? "38;5;203" : "38;5;244";

  let bar = "";
  for (let i = 0; i < BAR_WIDTH; i++) {
    if (i === markerIdx) bar += paint("|", markerColor);
    else if (i < filled) bar += paint("█", fillColor);
    else bar += paint("░", "38;5;238");
  }
  return { bar, label: paint(`${Math.round(clamped)}%`, fillColor) };
}

function gradientModelName(name) {
  if (!name) return "";
  const chars = [...name];
  const colored = chars.map((ch, i) => {
    const slot = Math.min(MODEL_RAMP.length - 1, Math.floor((i / chars.length) * MODEL_RAMP.length));
    return `\x1b[1m\x1b[38;5;${MODEL_RAMP[slot]}m${ch}`;
  });
  return colored.join("") + "\x1b[0m";
}

function git(dir, ...args) {
  try {
    return execFileSync("git", ["-C", dir, ...args], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
      windowsHide: true,
    }).trim();
  } catch {
    return null;
  }
}

function gitParts(dir) {
  if (!dir || !existsSync(dir)) return { branch: "", changes: "" };

  let head = git(dir, "rev-parse", "--abbrev-ref", "HEAD");
  if (head === "HEAD") head = git(dir, "rev-parse", "--short", "HEAD");
  const branch = head ? paint(head, "38;5;109") : "";

  let ins = 0;
  let del = 0;
  for (const line of (git(dir, "diff", "--numstat", "HEAD") ?? "").split("\n")) {
    const [added, removed] = line.split("\t");
    if (/^\d+$/.test(added ?? "")) ins += Number(added);
    if (/^\d+$/.test(removed ?? "")) del += Number(removed);
  }
  const changes = ins > 0 || del > 0 ? paint(`(+${ins},-${del})`, "38;5;178") : "";
  return { branch, changes };
}

function timeUntil(resetsAtSeconds) {
  if (!isNumber(resetsAtSeconds)) return null;
  const totalMinutes = Math.floor((resetsAtSeconds * 1000 - Date.now()) / 60000);
  if (totalMinutes <= 0) return "0m";
  const days = Math.floor(totalMinutes / 1440);
  const hours = Math.floor((totalMinutes % 1440) / 60);
  const minutes = totalMinutes % 60;
  const parts = [];
  if (days > 0) parts.push(`${days}d`);
  if (hours > 0) parts.push(`${hours}h`);
  parts.push(`${minutes}m`);
  return parts.join(" ");
}

function usagePart(label, window) {
  if (!isNumber(window?.used_percentage)) return "";
  const left = timeUntil(window.resets_at);
  const text = `${label}: ${Math.round(window.used_percentage)}%` + (left ? ` (r: ${left})` : "");
  return paint(text, "38;5;111");
}

const terminalColumns = () => Number(process.env.COLUMNS) || process.stdout.columns || 0;

const status = parseStatus(await readStdin());

const { bar, label } = contextBar(status.context_window?.used_percentage);
const leftParts = [gradientModelName(status.model?.display_name), bar, label];
if (status.effort?.level) leftParts.push(paint(status.effort.level, "38;5;96"));
let line1 = leftParts.filter(Boolean).join("  ");

const { branch, changes } = gitParts(status.workspace?.current_dir || status.cwd);
const right = [branch, changes].filter(Boolean).join("  ");
if (right) {
  const pad = Math.max(1, terminalColumns() - 6 - visibleLength(line1) - visibleLength(right));
  line1 += " ".repeat(pad) + right;
}

const line2 = [usagePart("5-hour", status.rate_limits?.five_hour), usagePart("weekly", status.rate_limits?.seven_day)]
  .filter(Boolean)
  .join(paint(" | ", "38;5;240"));

process.stdout.write([line1, line2].filter(Boolean).join("\n") + "\n");
