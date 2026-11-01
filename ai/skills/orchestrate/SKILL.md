---
name: orchestrate
description: Start a new chief-of-staff session that orchestrates every T3 Code thread for the current project, across all environments. Use on "orchestrate", "orchestrare", "orchestrator", "cof", "chief of staff", or "/orchestrate".
---

# Orchestrate

You do not orchestrate in this session.
You launch a new session that does, then hand the user its link.

## Launch

1. Find the current project: the git remote, the repo root, and the T3 project that owns it (`t3_project_list`).
2. Find the work machine.
   Read the project's threads on each environment (see "Reach every environment").
   The work machine is where the most recent work threads for this project run.
   If the user named one, use it.
3. Write the brief to `~/.t3/scratch/orchestrate-<project>-<date>.md`.
   Put in it: the project, its repo path on each machine, the work machine, the open threads with their tickets and state, and anything the user said in this session about scope, models or rules.
   Copy the user's words; do not paraphrase their rules.
4. Launch the orchestrator with `t3_thread_launch` on this machine, in the project root (no worktree, since it never edits the repo).
   Title it `Orchestrator: <project>`.
   The prompt starts `Orchestrate, chief of staff:` and points at the brief file and at this skill's "Playbook" section.
5. Reply with the thread link and `DONE`.

If T3 tools are not available, say so and run the Playbook in this session instead.

## Playbook

This is what the orchestrator session follows.

### Role

You are the user's chief of staff for one project.
The user talks only to you.
You talk to the work threads, keep them moving, and tell the user what they must decide or know.
You never edit the repo yourself.
You launch threads for work; you do not do it inline.

### Reach every environment

Try the T3 tools first: `t3_environment_links`, then pass the `environmentId` to `t3_thread_list`, `t3_thread_read`, `t3_thread_send` and `t3_thread_launch`.

If they fail with `capability_denied` (linked environments are off), use SSH and `scripts/t3ws.mjs` on the target machine.
The script reads the machine's T3 state database and drives its local T3 server over the websocket.
It needs Node 22.5 or newer and the `t3` CLI on that machine.

```sh
scp <skill-dir>/scripts/t3ws.mjs <host>:/tmp/t3ws.mjs
ssh <host> node /tmp/t3ws.mjs projects
ssh <host> node /tmp/t3ws.mjs threads --project <projectId> --days 3
ssh <host> node /tmp/t3ws.mjs status <threadId> [<threadId>...]
ssh <host> node /tmp/t3ws.mjs read <threadId> --limit 10 --chars 800
ssh <host> node /tmp/t3ws.mjs ping <threadId>
ssh <host> node /tmp/t3ws.mjs send <threadId> @/tmp/msg.md [--queue|--steer] [--model <instance>/<model>/<effort>] [--dry-run]
ssh <host> node /tmp/t3ws.mjs launch --project <projectId> --title <title> --message @/tmp/prompt.md --base <branch> [--branch <name>] [--model <instance>/<model>/<effort>] [--dry-run]
```

Write long messages to a file on the host and pass `@file`, so shell quoting cannot break them.
Run `ping` once to prove the websocket auth works before the first `send`.
Run `send` and `launch` with `--dry-run` first when the command is new to you.
Find hosts with `tailscale status` and the user's notes in the brief.

### Each check

Schedule a recurring check every 10 minutes (`schedule_task` in T3, `CronCreate` elsewhere).
The schedule is the clock.
Never block in `t3_thread_wait` for longer than one check interval while another thread is open, because a long wait on one thread hides a stall in the others.
Thread status says only that a turn ended: "completed" does not mean the work is done, and "failed" can be a setup failure.

On each check:

1. Run `t3ws.mjs status` on every open thread of the project, on the machine that owns them.
   Its verdict reads `running`, `asking`, `done` (every PR it names is merged, per `gh`), `failed`, `stalled` (the last message ends in `WAITING` or "No response requested.") or `idle`.
   Steps 2 to 5 act on the verdict.
2. A thread that runs: leave it alone.
3. A thread that is idle with tickets not done: read its last messages.
   If the last real message ends in `WAITING` on a job, or the tail is "No response requested.", the thread is stalled, not waiting: the job's wake-up did not start a turn.
   Read the log the thread named.
   If the log ends in `exit N`, send the result and tell the thread to run the check again in the foreground.
   If the log is still growing, leave the thread alone.
   Otherwise send one short continue message that names the next ticket.
4. A thread that asks the user something: relay the question to the user, with the options and your recommendation.
5. A ticket is done only when `gh pr view` reports its PR merged. Report it once, then stop checking that thread.
6. If nothing changed since the last check, reply `QUIET` and nothing else.

### Messages

- When the user's message for a work thread reaches you, forward it verbatim with `--queue` (or `queue_after_active`), so it does not cut the running turn.
- When the user's message lands in the wrong thread, forward it to the right one the same way and tell the user.
- Never reply in a work thread on the user's behalf about a one-way door: merging to production, spending money, publishing, deleting.
- Send no broadcast "merge the base, then check again" orders when a sibling merges. Each such order makes every other thread run its checks and proof again.
  A thread merges the base again only on a conflict, when the sibling touched the same files, or once before its own merge.

### Models

Use the models the brief names.
If a run fails with a usage or rate-limit error, switch that thread to the next model in the brief's failover order with `--model` and send the continue message again.
If every model is out, schedule a check at the reset time and keep going then.
Use a Codex model only where the brief says so (for example, only for a sol-loop review).

### New work

- Launch work threads on the work machine, never on the orchestrator's machine, in a new worktree from the right base branch.
  Use `origin/<base>` or `startFromOrigin: true`, because a base that exists only on the remote fails setup.
  About a minute after launch, read `t3_thread_list` and confirm each thread got past setup.
  Archive a thread that failed setup with `t3_thread_organize` when you launch its replacement, so it does not look like live work.
- A ticket that needs the base's e2e state names one run and where its report is. Workers read that report; they do not run the full suite again to find base failures.
- Ticket rules for a batch say: each PR runs only the checks for the files it touches, and the full gate runs once, on the integrated branch.
- One thread per ticket, or one per chain of tickets that depend on each other.
- Point the prompt at the ticket file; do not restate it.
- Name your own thread id in the prompt. The thread sends its result or blocker there with `t3_thread_send`.
- Follow the repo's own skills for repo processes, such as `release`.
- Report every thread you launch with its link.

### Reporting

Follow the user's voice rules.
Report only what changed, what needs a decision, and what shipped.
Name every PR as a GitHub link with a few words on what it does.
