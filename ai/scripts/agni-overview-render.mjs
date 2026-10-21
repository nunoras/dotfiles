const CLOSED_STATES = new Set(["landed", "done", "cancelled", "canceled"]);

const MOVING_WORDS = {
  proposed: "Proposed",
  approved: "Queued",
  running: "Building",
  validating: "Checking",
  reviewing: "Reviewing",
  fixing: "Fixing",
  validated: "Validated",
  pr_open: "PR open",
};

const DETAIL_LIMIT = 240;

export function projectAt(projects, cwd) {
  return projects.find((project) => cwd === project.path || cwd.startsWith(`${project.path}/`))?.name ?? null;
}

export function activeRows(rows) {
  return rows.filter((row) => !CLOSED_STATES.has(row.state));
}

export function overviewFingerprint(rows) {
  return activeRows(rows)
    .map((row) => `${row.project}/${row.id}|${row.state}|${row.round}`)
    .sort()
    .join("\n");
}

function escapeHtml(text) {
  return text.replace(/[&<>"]/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[char]);
}

function clip(text) {
  return text.length > DETAIL_LIMIT ? `${text.slice(0, DETAIL_LIMIT - 3).trimEnd()}...` : text;
}

function questionText(row) {
  const asked = row.waitsOn.replace(/^an answer to "/, "").replace(/"$/, "");
  return clip(asked.split(/(?<=\?)\s/)[0]);
}

function heldReason(row) {
  return clip(row.waitsOn.replace(/^a person:?\s*/, "") || "held for a person");
}

function pullRequestLabel(row) {
  const number = row.waitsOn.match(/pull request #(\d+)/)?.[1];
  return number ? `PR #${number}` : "";
}

const STATE_KINDS = {
  proposed: "queue",
  approved: "queue",
  running: "build",
  fixing: "build",
  validating: "check",
  reviewing: "review",
  validated: "ready",
  pr_open: "ready",
  waiting_on_question: "ask",
  failed: "held",
};

const CHIP_GROUPS = { build: "run", check: "run", review: "run", queue: "wait", ready: "ok", ask: "q", held: "held" };

function stateKind(row) {
  return STATE_KINDS[row.state] ?? "queue";
}

function rowHtml(row, pill, detail, homeProject) {
  const kind = stateKind(row);
  const project = row.project === homeProject ? "" : `<b>${escapeHtml(row.project)}</b> `;
  const round = Number(row.round) > 0 ? ` r${row.round}` : "";
  const detailHtml = detail ? `<span class="detail">${escapeHtml(detail)}</span>` : "";
  return `<div class="row ${kind}"><span class="state"><i class="mark"></i>${pill}<span class="round">${round}</span></span><span class="title">${escapeHtml(row.title)}${detailHtml}</span><span class="id">${project}${escapeHtml(row.id)}</span></div>`;
}

function chip(count, label, kind) {
  return count > 0 ? `<span class="chip ${kind}"><i class="mark"></i><b>${count}</b> ${label}</span>` : "";
}

const STYLE = `
:root { color-scheme: light dark; --blue: color-mix(in oklab, #3d82c4 80%, var(--foreground)); --green: color-mix(in oklab, #2f9a62 80%, var(--foreground)); --amber: color-mix(in oklab, #c9861a 82%, var(--foreground)); --red: color-mix(in oklab, #d0434f 82%, var(--foreground)); }
body { margin: 0; font: 12px/16px var(--font-sans, system-ui, sans-serif); color: var(--foreground); -webkit-font-smoothing: antialiased; }
.top { display: flex; flex-wrap: wrap; align-items: center; gap: 2px 12px; margin-bottom: 6px; color: var(--muted-foreground); font-variant-numeric: tabular-nums; }
.chip { display: inline-flex; align-items: center; gap: 5px; }
.chip b { font-weight: 600; color: var(--foreground); }
.asof { margin-left: auto; font-size: 11px; }
h3 { margin: 8px 0 0; font-size: 11px; line-height: 16px; font-weight: 600; color: var(--muted-foreground); }
.row { --tone: var(--muted-foreground); display: grid; grid-template-columns: 92px minmax(0, 1fr) auto; gap: 10px; align-items: baseline; padding: 3px 0; }
.row + .row { border-top: 1px solid color-mix(in oklab, var(--border) 50%, transparent); }
.state { display: inline-flex; align-items: center; gap: 6px; color: var(--tone); font-weight: 500; white-space: nowrap; align-self: start; height: 16px; }
.round { color: var(--muted-foreground); font-weight: 400; }
.title { min-width: 0; overflow: hidden; text-overflow: ellipsis; }
.held .title { color: var(--muted-foreground); }
.detail { display: block; font-size: 11px; line-height: 14px; color: var(--muted-foreground); }
.id { font-size: 11px; color: var(--muted-foreground); white-space: nowrap; font-variant-numeric: tabular-nums; }
.id b { font-weight: 500; color: var(--foreground); }
.mark { position: relative; display: inline-block; flex: none; width: 8px; height: 8px; border-radius: 50%; box-sizing: border-box; color: var(--tone); }
.build, .check, .review, .chip.run { --tone: var(--blue); }
.ready, .chip.ok { --tone: var(--green); }
.ask, .chip.q { --tone: var(--amber); }
.held, .chip.held { --tone: var(--red); }
.build .mark, .chip.run .mark { border: 1.5px solid color-mix(in oklab, var(--tone) 30%, transparent); border-top-color: var(--tone); }
.check .mark { background: var(--tone); }
.review .mark { border: 1.5px solid color-mix(in oklab, var(--tone) 30%, transparent); }
.review .mark::after { content: ""; position: absolute; top: 50%; left: 50%; width: 3px; height: 3px; margin: -1.5px; border-radius: 50%; background: var(--tone); transform: translateX(-1.5px); }
.queue .mark, .chip.wait .mark { border: 1.5px solid var(--tone); }
.ready .mark, .chip.ok .mark { width: 8px; height: 5px; border-radius: 0; border-left: 1.5px solid var(--tone); border-bottom: 1.5px solid var(--tone); transform: translateY(-1px) rotate(-45deg); }
.ask .mark, .chip.q .mark, .held .mark, .chip.held .mark { background: var(--tone); }
@media (prefers-reduced-motion: no-preference) {
  .build .mark { animation: spin .9s linear infinite; }
  .check .mark { animation: tick 1.2s ease-in-out infinite; }
  .review .mark::after { animation: scan 1.6s ease-in-out infinite alternate; }
  .queue .mark { animation: fade 3s ease-in-out infinite; }
  .ready .mark { animation: settle .6s ease-out 1; }
  .ask .mark { animation: blink 1.4s ease-in-out infinite; }
  .held .mark { animation: nudge 5s ease-in-out infinite; }
}
@keyframes spin { to { transform: rotate(1turn); } }
@keyframes tick { 0%, 100% { transform: scale(.55); } 50% { transform: scale(1); } }
@keyframes scan { to { transform: translateX(1.5px); } }
@keyframes fade { 50% { opacity: .35; } }
@keyframes settle { from { opacity: 0; transform: translateY(-1px) rotate(-45deg) scale(.4); } }
@keyframes blink { 50% { opacity: .25; } }
@keyframes nudge { 0%, 90%, 100% { transform: none; } 93% { transform: translateX(-1.5px); } 96% { transform: translateX(1.5px); } }
.empty { color: var(--muted-foreground); padding: 3px 0; }
details summary { cursor: pointer; list-style: none; }
details summary::-webkit-details-marker { display: none; }
details summary h3 { display: inline-flex; align-items: center; gap: 6px; }
details summary h3::after { content: ""; width: 4px; height: 4px; border-right: 1.5px solid currentColor; border-bottom: 1.5px solid currentColor; transform: translateY(-1px) rotate(45deg); }
details[open] summary h3::after { transform: translateY(1px) rotate(225deg); }
@media (max-width: 480px) { .row { grid-template-columns: 84px minmax(0, 1fr); } .id { display: none; } }
`;

export function renderOverview({ rows, time, homeProject, scopeLabel }) {
  const active = activeRows(rows);
  const moving = active.filter((row) => MOVING_WORDS[row.state]);
  const questions = active.filter((row) => row.state === "waiting_on_question");
  const held = active.filter((row) => row.state === "failed");
  const count = (group) => moving.filter((row) => CHIP_GROUPS[stateKind(row)] === group).length;

  const sections = [];
  if (moving.length > 0) {
    sections.push(
      `<h3>Moving</h3>${moving.map((row) => rowHtml(row, MOVING_WORDS[row.state], pullRequestLabel(row), homeProject)).join("")}`,
    );
  }
  if (questions.length > 0) {
    sections.push(
      `<h3>Needs your answer</h3>${questions.map((row) => rowHtml(row, "Question", questionText(row), homeProject)).join("")}`,
    );
  }
  if (held.length > 0) {
    sections.push(
      `<details><summary><h3>Held for a person (${held.length})</h3></summary>${held.map((row) => rowHtml(row, "Held", heldReason(row), homeProject)).join("")}</details>`,
    );
  }
  if (sections.length === 0) {
    sections.push(`<div class="empty">No active agni tasks.</div>`);
  }

  const chips = [
    chip(count("run"), "building", "run"),
    chip(count("wait"), "queued", "wait"),
    chip(count("ok"), "ready", "ok"),
    chip(questions.length, questions.length === 1 ? "needs an answer" : "need an answer", "q"),
    chip(held.length, "held", "held"),
  ].join("");

  return `<!doctype html><html><head><meta charset="utf-8"><style>${STYLE}</style></head><body><div class="top">${chips}<span class="asof">${scopeLabel ? `${escapeHtml(scopeLabel)} · ` : ""}as of ${escapeHtml(time)}</span></div>${sections.join("")}</body></html>\n`;
}
