---
name: agni
description: Coordinate Agni tasks and sessions. Use to propose, approve, monitor, answer, land or retry tasks, run or review sessions, or manage profiles and roles.
---

# Agni

`agni` runs coding-agent work on your own machine: you propose a task, approve it, and the background service drives it through a worker turn, validation, review and delivery.
Every command prints TOON on stdout, and every error prints TOON on stderr with a non-zero exit code.
Each result ends with `help[]` lines naming the useful next commands.

A task moves through `proposed`, `approved`, `running`, `validating`, `reviewing`, `validated` and `pr_open` to `landed`; a `plan` task ends `done` after its worker turn.
A failed validation or a `changes` review sends the task back for a rework round; when the rounds are spent Agni asks whether to allow more.
Run `agni status` first and read its `tasks` table: the `state` column says where each task is, and `waitsOn` names what it is waiting for.

## Your part

- For managed tasks, turn the user's request into a complete brief; workers change code in their own worktrees.
- For direct sessions, follow the user's requested scope and review the resulting work.
- Approve a task without asking when the user asked for the work or their standing instructions (CLAUDE.md, AGENTS.md) authorize approving; otherwise ask the user first. Ask before you change a task they already approved.
- Agni owns every state change: report a task's state from `agni status`, never from memory.

## Check the machine

- `agni status` reports the service, projects, tasks, attempts, validations, reviews, questions and pauses, and its `help[]` lines name the next command for every pause.
- Approved work runs only while the service is up: `agni service status` says which, `agni service start` starts it, `agni service install` also starts it at every login, and `agni service restart` restarts it from the current `agni` build.

## Propose

- `agni project propose --title "<title>" --intent "<intent>"` files a task that waits for approval; use `--intent-file <path>` for a long brief.
- The intent is the whole brief: write what to build, where, and what proves it, because the worker sees no other context.
- The role is `build` unless `--role plan|fix` says otherwise, and a project with dispatch rules in its `.agni.toml` picks the role itself; review tasks run themselves and cannot be proposed.
- `--after <task>` holds this task until the named one finishes and can be repeated, and `--project <name>` names the project when several are registered.

## Approve

- `agni project approve <task>...` lets the service run proposed tasks; it dispatches each when a slot is free.
- `agni project stop <task>...` ends a task's workers and keeps its worktree, branch and records.

## Wait

- Poll `agni status`; its attempts, validations and reviews tables show execution details, and questions and pauses show what needs a person.
- `pool_full` means every worktree is taken: run `agni project purge` to clear merged worktrees or raise `max_trees` in the project's `treehouse.toml`; the task resumes on its own once a slot frees.
- Watch a running turn with `agni agent tail <session>`, and `agni agent status <session>` reports one without blocking.

## Keep the user posted

- While any task is not yet `landed`, `done`, `validated` or `failed`, keep `agni status --wait 600` running through your shell tool in the background, and start it again each time it returns.
- It returns `wait.result: changed` as soon as a task, attempt, review, validation, question or pause changes, and `timeout` after ten quiet minutes.
- On `changed`, post the summary line and one line per task whose state, round, review verdict or question changed since your last update; on `timeout`, post only the summary line.
- Keep each update this short, with no emoji and no prose around it:

```
10m  2 running, 1 reviewing (round 2/3)
>    #42 add-login   reviewing -> changes (Sol, 2 findings)
+    #41 parser-fix  landed
x    #44 docs-sweep  failed: validation exit 1
?    #43 add-cache   needs you: "keep the old API?"
```

- The first line counts tasks by state and gives the minutes since your last update; `>` marks a state change, `+` a task that finished, `x` a failure, and `?` a question or pause that needs the user, always last.
- Pad task names so the states line up, and write the cause of every `x` and the exact question of every `?`.

## Answer

- A task at `waiting_on_question` has its question and id in `agni status`'s `questions` table.
- Answer it yourself only when the task's intent or the project's documents already settle it: `agni project answer <question-id> --text "<answer>"`.
- When the answer is a tradeoff, a scope change or a cost, ask the user and pass their answer with `--by user`.
- The task resumes on its own once every open question has an answer.
- When the answer is that a blocking review finding does not need fixing, also waive it: `agni project waive <task> --finding "<finding text>" --reason "<why>"`, with `--by user` when the user decided.
- Copy the finding's line from the review, with or without its `- blocking:` marker.
- The next review brief lists waived findings with their reason, a `changes` verdict whose only blocking findings are waived publishes the change, and `agni status <task>` shows them in its `waivers` table.

## Land

- GitHub delivery: after the review approves, the service pushes the task's branch, named after the work such as `feat/add-login`, and opens a pull request, and the task waits at `pr_open` for its merge.
- Merge the pull request on the forge; Agni marks the task `landed` when it sees the merge.
- When the pull request body lists files under `## Video` as waiting to be embedded, upload each through a browser signed in to GitHub and put the `https://github.com/user-attachments/assets/<id>` URL it returns on its own line under that heading.
- Local delivery: the task ends `validated` and keeps its branch for you to integrate yourself.
- `agni project land <task> --pr <url>` records a task whose work merged through a pull request Agni did not open.
- After landing, `agni project purge` previews the worktrees that are merged, clean and inactive, and `--confirm <plan>` with the plan it printed deletes them.

## Retry

- A failed validation or a `changes` review starts the task's next rework round on its own, up to the project's `review.rounds`.
- When the rounds are spent the task waits on a question that is the user's to answer: `continue` grants another budget of rounds, and `leave` ends the task `failed`.
- A `failed` task keeps its branch, worktree and validation output, and `waitsOn` and the `validations` table say why it failed.
- Read them before retrying: the failure is often the environment, not the change.
- `agni project retry <task> [--profile <profile>]` runs a failed task again on its branch with fresh rounds, once its cause is fixed.

## Run a session yourself

- `agni agent run --harness <harness> --model <model> "<prompt>"` runs a session; use `--profile <name>` or `--role <role>` to select configured settings.
- Use `--detach` for parallel or long sessions, then `agni agent wait <id>`; `agni agent ps` lists running sessions and `agni agent resume <id> "<prompt>"` continues a finished one. Check `agni agent run --help` for other options.

## Delegate inside a conversation

- Use direct sessions for independent work that should finish while the conversation continues. Start independent lanes together, name each model and task, and give every code-writing lane its own worktree.
- Ask each lane to save its full findings to a named file. Review its output and diff before reporting results, then record the verdict with `agni agent outcome <id>`.
- A native subagent is an alternative for Claude work when available; Agni will not record that session.

## Profiles, roles and accounts

- `agni profile` manages profiles; `agni role` manages role chains and prompts. Use `agni profile --help` or `agni role --help` for command options.
- `agni agent account` manages isolated harness accounts. `agni agent show`, `outcome`, `export` and `stats` inspect or record completed sessions; use `agni agent --help` for options.

Report only what the command output says.
