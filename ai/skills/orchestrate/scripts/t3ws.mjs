#!/usr/bin/env node
import crypto from "node:crypto";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";

const USAGE = `t3ws <command> [args]

Reads and drives T3 Code threads on the machine it runs on, through its state
database and its local websocket. Run it on the machine that owns the threads,
for example: ssh <host> node ~/.claude/skills/orchestrate/scripts/t3ws.mjs threads

Commands:
  projects                              List projects
  threads [--project <id>] [--days <n>] List live threads, newest first, with the latest run
  status <threadId>...                  Verdict (running, asking, done, failed, stalled, idle), latest run, last message, PRs with live gh state
  read <threadId> [--limit <n>]         Last messages of a thread, oldest first
  send <threadId> <text|@file> [--queue] [--steer] [--model <instance>/<model>[/<effort>]]
  launch --project <id> --title <t> --message <text|@file> [--base <ref>] [--branch <b>] [--model ...]
  ping <threadId>                       Check the websocket and auth with one read
  questions <threadId>                  Pending questions the thread asks the user
  answer <threadId> <json|@file>        Answer the pending question, as {"<question>": "<answer>"}

Flags:
  --chars <n>   Cap each message at n characters. Default 400
  --dry-run     Print the websocket payload instead of sending it
  --json        Print JSON instead of text`;

const HOME = os.homedir();
const DB_PATH = process.env.T3_STATE_DB ?? path.join(HOME, ".t3", "userdata", "statev2.sqlite");
const WS_PORT = Number(process.env.T3_WS_PORT ?? 3773);

function parseArgs(argv) {
  const positional = [];
  const flags = {};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (!arg.startsWith("--")) {
      positional.push(arg);
      continue;
    }
    const name = arg.slice(2);
    const next = argv[i + 1];
    if (next === undefined || next.startsWith("--")) flags[name] = true;
    else {
      flags[name] = next;
      i++;
    }
  }
  return { positional, flags };
}

const textArg = (value) => (typeof value === "string" && value.startsWith("@") ? fs.readFileSync(value.slice(1), "utf8") : value);

const clip = (text, chars) => {
  const flat = (text ?? "").replace(/\s+/g, " ").trim();
  return flat.length > chars ? `${flat.slice(0, chars)}…` : flat;
};

function parseModel(spec) {
  const [instanceId, model, effort] = String(spec).split("/");
  if (!instanceId || !model) throw new Error(`--model wants <instance>/<model>[/<effort>], got ${spec}`);
  const options = effort ? [{ id: "effort", value: effort }, { id: "fastMode", value: false }] : [];
  return { instanceId, model, options };
}

function openDb() {
  if (!fs.existsSync(DB_PATH)) throw new Error(`no T3 state database at ${DB_PATH}`);
  return new DatabaseSync(DB_PATH, { readOnly: true });
}

function latestRun(db, threadId) {
  return db
    .prepare(
      "select run_id as runId, ordinal, provider_instance_id as instance, status, requested_at as requested, completed_at as completed, payload_json from orchestration_v2_projection_runs where thread_id = ? order by ordinal desc limit 1",
    )
    .get(threadId);
}

function steerableRun(db, threadId) {
  return db
    .prepare("select run_id as runId from orchestration_v2_projection_runs where thread_id = ? and status in ('running', 'waiting') order by ordinal desc limit 1")
    .get(threadId);
}

function runFailure(run) {
  if (!run || run.status !== "failed") return null;
  const payload = JSON.parse(run.payload_json ?? "{}");
  return payload.failure?.message ?? payload.error?.message ?? payload.failure ?? payload.error ?? null;
}

function lastAssistant(db, threadId) {
  return db
    .prepare(
      "select created_at as at, json_extract(payload_json, '$.text') as text from orchestration_v2_projection_messages where thread_id = ? and role = 'assistant' and streaming = 0 order by created_at desc limit 1",
    )
    .get(threadId);
}

function pullRequests(db, threadId) {
  return db
    .prepare("select url, json_extract(snapshot_json, '$.state') as state from projection_thread_pull_requests where thread_id = ? order by number")
    .all(threadId);
}

function threadRow(db, threadId) {
  return db
    .prepare(
      "select t.thread_id as id, t.title, t.project_id as project, t.provider_instance_id as instance, t.updated_at as updated, json_extract(t.payload_json, '$.lineage.relationshipToParent') as relation from orchestration_v2_projection_threads t where t.thread_id = ?",
    )
    .get(threadId);
}

function cmdProjects(db) {
  return db.prepare("select project_id as id, title, workspace_root as root from projection_projects where deleted_at is null order by title").all();
}

function cmdThreads(db, flags) {
  const days = Number(flags.days ?? 3);
  const since = new Date(Date.now() - days * 86400000).toISOString();
  const rows = db
    .prepare(
      `select thread_id as id, title, project_id as project, updated_at as updated
       from orchestration_v2_projection_threads
       where archived_at is null and deleted_at is null and updated_at >= ?
         and coalesce(json_extract(payload_json, '$.lineage.relationshipToParent'), '') != 'subagent'
         ${flags.project ? "and project_id = ?" : ""}
       order by updated_at desc`,
    )
    .all(...[since, flags.project].filter(Boolean));
  return rows.map((row) => {
    const run = latestRun(db, row.id);
    return { ...row, run: run ? `${run.ordinal} ${run.status} ${run.instance}` : "none" };
  });
}

const ACTIVE_RUN = ["queued", "preparing", "starting", "running", "waiting"];
const STALLED_TAIL = /(\bWAITING\b[^\n]*|No response requested\.)\s*$/;

function liveState(url, snapshotState) {
  const viewed = spawnSync("gh", ["pr", "view", url, "--json", "state", "--jq", ".state"], { encoding: "utf8" });
  const state = viewed.status === 0 ? viewed.stdout.trim() : "";
  return state ? { state, source: "gh" } : { state: snapshotState ?? "unknown", source: "t3 snapshot" };
}

function mentionedPullRequests(text) {
  const urls = (text ?? "").match(/https:\/\/github\.com\/[\w.-]+\/[\w.-]+\/pull\/\d+/g) ?? [];
  return [...new Set(urls)].map((url) => ({ url, state: null }));
}

function verdict(run, message, question, prs) {
  if (run && ACTIVE_RUN.includes(run.status)) return "running";
  if (question) return "asking";
  if (prs.length > 0 && prs.every((pr) => String(pr.state).toUpperCase() === "MERGED")) return "done";
  if (run?.status === "failed") return "failed";
  if (message && STALLED_TAIL.test(message.text ?? "")) return "stalled";
  return "idle";
}

function cmdStatus(db, ids, chars) {
  return ids.map((id) => {
    const thread = threadRow(db, id);
    if (!thread) return { id, error: "no such thread" };
    const run = latestRun(db, id);
    const message = lastAssistant(db, id);
    const linked = pullRequests(db, id);
    const named = linked.length > 0 ? linked : mentionedPullRequests(message?.text);
    const prs = named.map((pr) => ({ url: pr.url, ...liveState(pr.url, pr.state) }));
    return {
      id,
      title: thread.title,
      verdict: verdict(run, message, pendingQuestion(db, id), prs),
      run: run ? { ordinal: run.ordinal, status: run.status, instance: run.instance, requested: run.requested, completed: run.completed, failure: runFailure(run) } : null,
      lastMessage: message ? { at: message.at, text: clip(message.text, chars) } : null,
      pullRequests: prs,
    };
  });
}

function cmdRead(db, id, limit, chars) {
  return db
    .prepare(
      "select created_at as at, role, json_extract(payload_json, '$.text') as text from orchestration_v2_projection_messages where thread_id = ? and streaming = 0 order by created_at desc limit ?",
    )
    .all(id, limit)
    .reverse()
    .map((row) => ({ ...row, text: clip(row.text, chars) }));
}

function issueToken() {
  const issued = spawnSync("t3", ["auth", "session", "issue", "--token-only", "--ttl", "10m", "--label", "orchestrate"], { encoding: "utf8" });
  const token = (issued.stdout ?? "").trim();
  if (issued.status !== 0 || token.length < 20) throw new Error(`t3 auth session issue failed: ${(issued.stderr ?? "").slice(0, 300)}`);
  return token;
}

function encodeFrame(text) {
  const payload = Buffer.from(text);
  const mask = crypto.randomBytes(4);
  let header;
  if (payload.length < 126) header = Buffer.from([0x81, 0x80 | payload.length]);
  else if (payload.length < 65536) {
    header = Buffer.alloc(4);
    header[0] = 0x81;
    header[1] = 0x80 | 126;
    header.writeUInt16BE(payload.length, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x81;
    header[1] = 0x80 | 127;
    header.writeBigUInt64BE(BigInt(payload.length), 2);
  }
  const masked = Buffer.alloc(payload.length);
  for (let i = 0; i < payload.length; i++) masked[i] = payload[i] ^ mask[i % 4];
  return Buffer.concat([header, mask, masked]);
}

function decodeFrames(buffer) {
  const frames = [];
  let offset = 0;
  while (offset + 2 <= buffer.length) {
    const opcode = buffer[offset] & 0x0f;
    let length = buffer[offset + 1] & 0x7f;
    let start = offset + 2;
    if (length === 126) {
      if (buffer.length < start + 2) break;
      length = buffer.readUInt16BE(start);
      start += 2;
    } else if (length === 127) {
      if (buffer.length < start + 8) break;
      length = Number(buffer.readBigUInt64BE(start));
      start += 8;
    }
    if (buffer.length < start + length) break;
    if (opcode === 0x1) frames.push(buffer.subarray(start, start + length).toString("utf8"));
    offset = start + length;
  }
  return { frames, rest: buffer.subarray(offset) };
}

async function rpc(tag, payload) {
  const token = issueToken();
  const socket = net.connect(WS_PORT, "127.0.0.1");
  const id = crypto.randomUUID();
  let buffer = Buffer.alloc(0);
  let upgraded = false;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      socket.destroy();
      reject(new Error(`no answer to ${tag} within 60s`));
    }, 60000);
    const finish = (fn, value) => {
      clearTimeout(timer);
      socket.end();
      fn(value);
    };
    socket.on("error", (error) => finish(reject, error));
    socket.on("connect", () => {
      socket.write(
        [
          "GET /ws?orchestrationProtocol=2 HTTP/1.1",
          `Host: 127.0.0.1:${WS_PORT}`,
          "Upgrade: websocket",
          "Connection: Upgrade",
          `Sec-WebSocket-Key: ${crypto.randomBytes(16).toString("base64")}`,
          "Sec-WebSocket-Version: 13",
          `Authorization: Bearer ${token}`,
          "",
          "",
        ].join("\r\n"),
      );
    });
    socket.on("data", (chunk) => {
      buffer = Buffer.concat([buffer, chunk]);
      if (!upgraded) {
        const end = buffer.indexOf("\r\n\r\n");
        if (end < 0) return;
        const status = buffer.subarray(0, end).toString("utf8").split("\r\n")[0];
        if (!status.includes("101")) return finish(reject, new Error(`websocket upgrade refused: ${status}`));
        upgraded = true;
        buffer = buffer.subarray(end + 4);
        socket.write(encodeFrame(JSON.stringify({ _tag: "Request", id, tag, payload, headers: [] })));
      }
      const decoded = decodeFrames(buffer);
      buffer = Buffer.from(decoded.rest);
      for (const frame of decoded.frames) {
        let message;
        try {
          message = JSON.parse(frame);
        } catch {
          continue;
        }
        if ((message.id ?? message.requestId) !== id) continue;
        if (message.exit?._tag === "Success") return finish(resolve, message.exit.value);
        return finish(reject, new Error(`${tag} failed: ${JSON.stringify(message.exit ?? message).slice(0, 800)}`));
      }
    });
  });
}

function currentModel(db, threadId) {
  const row = db.prepare("select json_extract(payload_json, '$.modelSelection') as selection from orchestration_v2_projection_threads where thread_id = ?").get(threadId);
  return row?.selection ? JSON.parse(row.selection) : null;
}

async function cmdSend(db, positional, flags) {
  const [threadId, raw] = positional;
  if (!threadId || raw === undefined) throw new Error("send wants <threadId> <text|@file>");
  if (!threadRow(db, threadId)) throw new Error(`no such thread ${threadId}`);
  const modelSelection = flags.model ? parseModel(flags.model) : currentModel(db, threadId);
  if (!modelSelection) throw new Error("the thread has no model selection; pass --model");
  const run = latestRun(db, threadId);
  const active = run && ["queued", "preparing", "starting", "running", "waiting"].includes(run.status);
  const steerTarget = flags.steer && active ? steerableRun(db, threadId) : null;
  if (flags.steer && active && !steerTarget) throw new Error(`no running turn to steer; run ${run.ordinal} is ${run.status}, pass --queue`);
  const dispatchMode = active ? (steerTarget ? { type: "steer_active", targetRunId: steerTarget.runId } : { type: "queue_after_active" }) : { type: "start_immediately" };
  if (active && !flags.queue && !flags.steer) throw new Error(`run ${run.ordinal} is ${run.status}; pass --queue to send after it, or --steer to add it to the running turn`);
  const commands = [];
  if (flags.model) commands.push({ type: "thread.model-selection.set", commandId: crypto.randomUUID(), threadId, modelSelection });
  commands.push({
    type: "message.dispatch",
    commandId: crypto.randomUUID(),
    createdBy: "user",
    creationSource: "mcp",
    threadId,
    messageId: crypto.randomUUID(),
    text: textArg(raw),
    attachments: [],
    modelSelection,
    dispatchMode,
  });
  if (flags["dry-run"]) return commands;
  const results = [];
  for (const command of commands) results.push({ type: command.type, result: await rpc("orchestration.dispatchCommand", command) });
  return results;
}

function pendingQuestion(db, threadId) {
  const request = db
    .prepare("select runtime_request_id as id, payload_json as payload from orchestration_v2_projection_runtime_requests where thread_id = ? and kind = 'user_input' and status = 'pending' order by created_at desc limit 1")
    .get(threadId);
  if (!request) return null;
  const nativeId = JSON.parse(request.payload).nativeRequestRef?.nativeId;
  const item = nativeId
    ? db.prepare("select payload_json as payload from orchestration_v2_projection_turn_items where payload_json like ? limit 1").get(`%${nativeId}%`)
    : null;
  const questions = item ? JSON.parse(item.payload).input?.questions ?? [] : [];
  return { requestId: request.id, questions };
}

function cmdQuestions(db, threadId) {
  const pending = pendingQuestion(db, threadId);
  if (!pending) return { pending: false };
  return {
    pending: true,
    questions: pending.questions.map((q) => ({ question: q.question, options: (q.options ?? []).map((o) => o.label) })),
  };
}

async function cmdAnswer(db, positional, flags) {
  const [threadId, raw] = positional;
  if (!threadId || raw === undefined) throw new Error("answer wants <threadId> <json|@file>");
  const pending = pendingQuestion(db, threadId);
  if (!pending) throw new Error(`thread ${threadId} has no pending question`);
  const command = {
    type: "runtime-request.respond",
    commandId: crypto.randomUUID(),
    threadId,
    requestId: pending.requestId,
    answers: JSON.parse(textArg(raw)),
  };
  if (flags["dry-run"]) return command;
  return await rpc("orchestration.dispatchCommand", command);
}

async function cmdLaunch(db, flags) {
  for (const name of ["project", "title", "message"]) if (!flags[name]) throw new Error(`launch wants --${name}`);
  const project = db.prepare("select default_model_selection_json as model from projection_projects where project_id = ?").get(flags.project);
  if (!project) throw new Error(`no such project ${flags.project}`);
  const modelSelection = flags.model ? parseModel(flags.model) : project.model ? JSON.parse(project.model) : null;
  if (!modelSelection) throw new Error("the project has no default model; pass --model");
  const workspaceStrategy = flags.base
    ? { type: "worktree", baseRef: flags.base, startFromOrigin: true, ...(flags.branch ? { branch: flags.branch } : {}) }
    : { type: "root" };
  const payload = {
    commandId: crypto.randomUUID(),
    creationSource: "mcp",
    projectId: flags.project,
    title: flags.title,
    modelSelection,
    runtimeMode: flags.runtime ?? "full-access",
    interactionMode: "default",
    workspaceStrategy,
    initialMessage: { messageId: crypto.randomUUID(), text: textArg(flags.message), attachments: [] },
  };
  if (flags["dry-run"]) return payload;
  const result = await rpc("orchestration.launchThread", payload);
  return { threadId: result.threadId, resumed: result.resumed };
}

function print(value, json) {
  if (json || typeof value !== "object") return console.log(JSON.stringify(value, null, 2));
  for (const item of Array.isArray(value) ? value : [value]) {
    if (item.lastMessage !== undefined || item.run?.status) {
      console.log(`== ${item.verdict ? `[${item.verdict}] ` : ""}${item.title ?? ""} ${item.id}`);
      if (item.error) console.log(`   ${item.error}`);
      if (item.run) console.log(`   run ${item.run.ordinal} ${item.run.status} on ${item.run.instance}, requested ${item.run.requested}${item.run.completed ? `, done ${item.run.completed}` : ""}`);
      if (item.run?.failure) console.log(`   failure: ${clip(JSON.stringify(item.run.failure), 300)}`);
      if (item.lastMessage) console.log(`   ${item.lastMessage.at}: ${item.lastMessage.text}`);
      for (const pr of item.pullRequests ?? []) console.log(`   PR ${pr.url} ${pr.state ?? ""}${pr.source ? ` (${pr.source})` : ""}`);
    } else console.log(Object.values(item).join(" | "));
  }
}

async function main() {
  const [command, ...rest] = process.argv.slice(2);
  const { positional, flags } = parseArgs(rest);
  const chars = Number(flags.chars ?? 400);
  if (!command || command === "help" || flags.help) return console.log(USAGE);
  const db = openDb();
  switch (command) {
    case "projects":
      return print(cmdProjects(db), flags.json);
    case "threads":
      return print(cmdThreads(db, flags), flags.json);
    case "status":
      return print(cmdStatus(db, positional, chars), flags.json);
    case "read":
      return print(cmdRead(db, positional[0], Number(flags.limit ?? 10), chars), flags.json);
    case "send":
      return print(await cmdSend(db, positional, flags), true);
    case "launch":
      return print(await cmdLaunch(db, flags), true);
    case "questions":
      return print(cmdQuestions(db, positional[0]), true);
    case "answer":
      return print(await cmdAnswer(db, positional, flags), true);
    case "ping": {
      const projection = await rpc("orchestration.getThreadProjection", { threadId: positional[0] });
      return print({ ok: true, thread: projection.thread?.title ?? null }, true);
    }
    default:
      throw new Error(`unknown command ${command}\n\n${USAGE}`);
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
