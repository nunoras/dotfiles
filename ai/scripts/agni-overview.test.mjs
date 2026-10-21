import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { activeRows, overviewFingerprint, projectAt, renderOverview } from "./agni-overview-render.mjs";

process.env.HOME = mkdtempSync(join(tmpdir(), "agni-overview-"));
const { hasWatchWork, overviewOn, overviewToggle, readWatched, setOverview, writeWatched } = await import(
  "./agni-watch-lib.mjs"
);

const task = (overrides) => ({ project: "myapp", id: "t-1", title: "A task", state: "running", round: "1", waitsOn: "", ...overrides });

test("groups active tasks and leaves closed ones out", () => {
  const html = renderOverview({
    time: "15:41",
    homeProject: "myapp",
    rows: [
      task({ id: "t-1", title: "Builds now" }),
      task({ id: "t-2", title: "Asks something", state: "waiting_on_question", waitsOn: 'an answer to "Which way? A or B"' }),
      task({ id: "t-3", title: "Gave up", state: "failed", waitsOn: "a person: the worker died" }),
      task({ id: "t-4", title: "Shipped already", state: "landed" }),
      task({ project: "agni", id: "t-5", title: "Waits its turn", state: "approved" }),
    ],
  });
  assert.match(html, /<h3>Moving<\/h3>.*Builds now.*Waits its turn/s);
  assert.match(html, /Needs your answer.*Which way\?<\/span>/s);
  assert.match(html, /Held for a person \(1\).*the worker died/s);
  assert.doesNotMatch(html, /Shipped already/);
  assert.match(html, /<b>agni<\/b> t-5/);
  assert.doesNotMatch(html, /<b>myapp<\/b>/);
  assert.match(html, /<b>1<\/b> building.*<b>1<\/b> queued/s);
});

test("escapes task text", () => {
  const html = renderOverview({ time: "1", homeProject: null, rows: [task({ title: "<script>x</script>" })] });
  assert.doesNotMatch(html, /<script>x/);
  assert.match(html, /&lt;script&gt;x/);
});

test("says so when nothing is active", () => {
  assert.match(renderOverview({ time: "1", homeProject: null, rows: [task({ state: "landed" })] }), /No active agni tasks/);
});

test("fingerprint moves on a state change and ignores closed tasks and order", () => {
  const rows = [task({ id: "t-1" }), task({ id: "t-2", state: "approved" })];
  assert.equal(overviewFingerprint(rows), overviewFingerprint([...rows].reverse()));
  assert.equal(overviewFingerprint(rows), overviewFingerprint([...rows, task({ id: "t-9", state: "landed" })]));
  assert.notEqual(overviewFingerprint(rows), overviewFingerprint([task({ id: "t-1", state: "reviewing" }), rows[1]]));
  assert.equal(activeRows(rows).length, 2);
});

test("overview stays on after the last watched task finishes", () => {
  const session = "s-overview";
  setOverview(session, { scope: "here", cwd: "/repo" });
  writeWatched(session, [{ project: "myapp", id: "t-1" }]);
  writeWatched(session, []);
  assert.deepEqual(overviewOn(session), { scope: "here", cwd: "/repo" });
  assert.equal(hasWatchWork(session), true);
  setOverview(session, null);
  assert.equal(overviewOn(session), null);
  assert.equal(hasWatchWork(session), false);
  assert.deepEqual(readWatched(session), []);
});

test("toggle matches a real run of the script only", () => {
  assert.equal(overviewToggle('node "$HOME/.claude/scripts/agni-overview.mjs"'), "all");
  assert.equal(overviewToggle('node "$HOME/.claude/scripts/agni-overview.mjs" --here'), "here");
  assert.equal(overviewToggle("cd x && node ~/.claude/scripts/agni-overview.mjs --off"), "off");
  assert.equal(overviewToggle("node --check agni-overview.mjs"), null);
  assert.equal(overviewToggle("cat agni-overview.mjs"), null);
  assert.equal(overviewToggle("node agni-overview-render.mjs"), null);
});

test("finds the project a directory sits in, not a sibling with a shared prefix", () => {
  const projects = [{ name: "agni", path: "/home/n/GitHub/agni" }, { name: "myapp", path: "/home/n/GitHub/MyApp" }];
  assert.equal(projectAt(projects, "/home/n/GitHub/MyApp"), "myapp");
  assert.equal(projectAt(projects, "/home/n/GitHub/MyApp/app/src"), "myapp");
  assert.equal(projectAt(projects, "/home/n/GitHub/agni-old"), null);
});

test("names the scope beside the time", () => {
  assert.match(renderOverview({ time: "15:51", homeProject: "x", scopeLabel: "myapp", rows: [] }), /myapp · as of 15:51/);
});

test("fingerprint ignores waitsOn text such as a new worker lease", () => {
  const before = [task({ waitsOn: "a worker turn in worktree lease `aaa`" })];
  const after = [task({ waitsOn: "a worker turn in worktree lease `bbb`" })];
  assert.equal(overviewFingerprint(before), overviewFingerprint(after));
});
