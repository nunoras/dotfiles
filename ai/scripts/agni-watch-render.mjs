import { isFinished } from "./agni-watch-lib.mjs";

const STATE_WORDS = {
  proposed: "Proposed",
  approved: "Queued",
  running: "Building",
  validating: "Checking",
  reviewing: "Reviewing",
  fixing: "Fixing",
  waiting_on_question: "Question for you",
  validated: "Validated",
  pr_open: "PR open",
  landed: "Landed",
  done: "Done",
  failed: "Failed",
  cancelled: "Cancelled",
  canceled: "Cancelled",
};

const PERSON_STATES = new Set(["waiting_on_question", "failed"]);

function sharedPrefix(titles) {
  const prefixes = titles.map((title) => title.match(/^([^:]{1,40}):\s+/)?.[1]);
  return prefixes.length > 0 && prefixes.every((prefix) => prefix && prefix === prefixes[0]) ? prefixes[0] : null;
}

function capitalize(text) {
  return text.charAt(0).toUpperCase() + text.slice(1);
}

function shortTitle(title, prefix) {
  const rest = prefix ? title.slice(title.indexOf(":") + 1).trim() : title;
  return capitalize(rest.replace(/\|/g, "/"));
}

function dependencyOf(waitsOn) {
  return waitsOn.match(/^dependency `([^`]+)`/)?.[1] ?? null;
}

export function pullRequestNumber(row) {
  return row.waitsOn.match(/pull request #(\d+)/)?.[1] ?? null;
}

export function needsPerson(row) {
  return PERSON_STATES.has(row.state) || row.waitsOn.startsWith("a person");
}

export function stateWords(row) {
  const word = STATE_WORDS[row.state] ?? capitalize(row.state.replace(/_/g, " "));
  const dependency = row.state === "approved" ? dependencyOf(row.waitsOn) : null;
  if (dependency) {
    return `${word} after ${dependency}`;
  }
  if (row.state === "approved" && row.waitsOn.startsWith("a retry")) {
    return "Queued for a retry";
  }
  const round = Number(row.round) > 0 && !isFinished(row) ? `, round ${row.round}` : "";
  return `${word}${round}`;
}

function summary(rows) {
  const counts = new Map();
  for (const row of rows) {
    const word = (STATE_WORDS[row.state] ?? row.state).replace(/^(?!PR)\w+/, (first) => first.toLowerCase());
    counts.set(word, (counts.get(word) ?? 0) + 1);
  }
  return [...counts].map(([word, count]) => `${count} ${word}`).join(", ");
}

export function render({ time, tracked, actions }) {
  const rows = tracked.filter(({ row }) => row).map(({ row }) => row);
  const missing = tracked.filter(({ row }) => !row).map(({ task }) => task.id);
  const projects = [...new Set(rows.map((row) => row.project))];
  const prefix = sharedPrefix(rows.map((row) => row.title));
  const label = [time, ...projects, ...(prefix ? [prefix] : [])].join(" · ");
  const lines = [label, ""];

  for (const row of rows.filter(needsPerson)) {
    lines.push(`**Needs you: ${row.id}.** ${capitalize(row.waitsOn.replace(/^a person: /, ""))}`, "");
  }
  if (missing.length > 0) {
    lines.push(`Not found in agni: ${missing.join(", ")}`, "");
  }
  if (rows.length > 0) {
    const multiProject = projects.length > 1;
    lines.push(multiProject ? "| Project | Task | What | Now |" : "| Task | What | Now |");
    lines.push(multiProject ? "|---|---|---|---|" : "|---|---|---|");
    for (const row of rows) {
      const cells = [row.id, shortTitle(row.title, prefix), stateWords(row)];
      lines.push(`| ${(multiProject ? [row.project, ...cells] : cells).join(" | ")} |`);
    }
  }

  const title = `${prefix ?? projects.join(", ")} · ${summary(rows)}`;
  lines.push("", `t3: title ${title}`);
  for (const action of actions) {
    lines.push(`t3: ${action}`);
  }
  return lines.join("\n");
}
