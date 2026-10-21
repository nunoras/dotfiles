#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { parseTable } from "./agni-watch-lib.mjs";
import { projectAt, renderOverview } from "./agni-overview-render.mjs";

if (process.argv.includes("--off")) {
  console.log("agni overview off");
  process.exit(0);
}

const result = spawnSync("agni", ["status"], { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
if (result.status !== 0) {
  console.error(result.stderr || "agni status failed");
  process.exit(result.status ?? 1);
}

const homeProject = projectAt(parseTable(result.stdout, "projects"), process.cwd());
const here = process.argv.includes("--here");
if (here && !homeProject) {
  console.error(`${process.cwd()} is not inside a project registered with agni`);
  process.exit(2);
}

const tasks = parseTable(result.stdout, "tasks");
const rows = here ? tasks.filter((row) => row.project === homeProject) : tasks;
const time = new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", hour12: false });
process.stdout.write(renderOverview({ rows, time, homeProject, scopeLabel: here ? homeProject : null }));
