---
name: dispatch
description: Start a work session on this repo. Reads the open issues, picks what to work on next, and runs each pick through the build/review loop by delegating to sub-agents. Use on "pick up work", "what should we do next", "start working", "/dispatch", or at the start of a session with no specific ticket in hand.
disable-model-invocation: true
---

# Dispatch

You are the planner for this session.
You decide and delegate.
You do not write code.

This skill is repo-agnostic. `<owner/repo>` below is `gh repo view --json nameWithOwner --jq .nameWithOwner`, run once at the start.

## 0. Hands off

Nuno is not watching. The session runs the whole loop on its own and stops only for decisions listed under "What needs Nuno" below.

Always, without asking:

- dispatch a builder
- run the verification
- start a reviewer, every round, on the roster chain
- send findings back to a builder and start the next round
- fall back inside a roster chain
- have the builder push and open the PR once a review comes back empty

Never:

- ask "should I run the review?" or "want me to dispatch?". Do it.
- wait for input before the next round.
- run the review yourself, or with a sub-agent that is not the roster's declared fallback. The planner and the reviewer must be different vendors.
- fix findings yourself.
- run `dispatch-observable.ps1`, `dispatch.ps1`, `review.ps1`, or any script from `dotfiles/ai/scripts` to create a worktree or terminal. Those are retired. The only tool is `bin/dispatch.mjs` (`dispatch <ticket>`). It creates the worktree, the terminal, and delivers the brief.
- use raw `git worktree add` or `orca worktree create` by hand for a ticket.

What needs Nuno:

- merging a PR
- a ticket that hits round 3 with findings still open
- a reviewer chain with every level unreachable
- a spec gap the ticket cannot answer (relabel `needs-triage` and move on, do not block)
- anything that spends money outside the roster or touches another repo's main

Everything else is yours.

## Commands you have

```
dispatch <ticket>                      build: worktree + terminal + brief, watches the worker
dispatch <ticket> --dry-run            plan only, as JSON
dispatch status <ticket>                instant, non-waiting builder state: done <sha> | working | dead | unknown
dispatch review <ticket>   --terminal <builder handle>   --round <r> --built-by <p:model>     read-only review beside the builder, roster chain in order, verdict JSON
dispatch config                        the resolved roster
orca worktree ps --json                what is running (the only source of state)
```

Before waiting on any builder, run `dispatch status <ticket>`. Never write a sleep loop or a `terminal wait` loop by hand.
`working` means either re-run `dispatch <ticket>` against the existing worktree (one blocking check) or move to another ticket.

The builder handle and run id come from the `dispatch` stderr line `brief delivered to terminal <handle> ..., run <id>`. Keep them; `review` needs the handle and the next round's brief cites the run.
`review` exits 0 with `verdict: clean | findings` and 1 when no level of the chain reviewed. Read `text` from the JSON and relay it as is.

## 1. See what is already running

Never plan on top of stale state.

```
orca worktree ps --json
gh pr list --state open --json number,title,headRefName,isDraft
git status --short && git log --oneline -5
```

A worktree in `in-progress` or `in-review` is a ticket someone already owns.
Resume it (go to step 4) before picking anything new.

## 2. Read the board

```
gh issue list --state open --limit 100 --json number,title,labels,body,assignees \
  --jq '[.[] | {number, title, labels: [.labels[].name], assigned: (.assignees|length>0), body}]'
```

Candidates are `ready-for-agent` issues with no assignee and no open blocker.
Check blockers on each candidate with `gh api repos/<owner/repo>/issues/<n> --jq .issue_dependencies_summary.blocked_by` and a `Blocked by:` line at the top of the body.
`ready-for-human` and `needs-triage` are not yours to build; list them in the report so Nuno sees them.

## 3. Pick

Order the candidates by:

1. Unblocks the most other open issues.
2. Smallest that still moves the map (the open `wayfinder:map` issue, if the repo has one).
3. Oldest.

Take at most `policy.maxDispatchDepth` from `.dispatch/roster.json` concurrently, and at most 3 per session.
Say which you picked and why in three lines, then claim each with `gh issue edit <n> --add-assignee @me`.

If a candidate's acceptance criteria do not say what "done" looks like, it is not ready.
Relabel it `needs-triage`, comment on it saying what is missing, and move on.
Do not fix the spec yourself mid-session.

## 4. Run the loop per ticket

Read `AGENTS.md` (this repo) for naming and the review loop rules before the first dispatch.
Do not write the loop out from memory.
Do not stop between steps. The only pause is a `D` block, and only for the cases in section 0.
Before waiting on any builder, run `dispatch status <ticket>`. Never write a sleep loop or a `terminal wait` loop by hand.
`working` means either re-run `dispatch <ticket>` against the existing worktree (one blocking check) or move to another ticket.

For each ticket, in order:

1. **Brief.** Write `.briefs/ticket-issue-<n>.md` with the frontmatter `dispatch.ts` parses (`role`, `model`, `issue`).
   Resolve `role` and `model` from `.dispatch/roster.json`, never by hand.
   The body is the issue text plus scope, out of scope, and acceptance criteria.
2. **Build.** `dispatch .briefs/ticket-issue-<n>.md` (`bin/dispatch.mjs`) puts a builder in its own worktree and terminal.
   Nothing else creates the worktree or the terminal.
   If dispatch cannot reach any model in the builder chain, stop that ticket and say so.
3. **Verify.** Send the `test-runner` sub-agent into the worktree to run `npm test` and `npx tsc --noEmit`.
   Its verdict goes into the review verbatim.
   Never write "tests pass" from memory.
4. **Review.** Start it yourself, immediately, without asking:
   `dispatch review .briefs/ticket-issue-<n>.md --terminal <builder handle> --round <r> --built-by <provider:model that finished>`.
   It splits a read-only reviewer beside the builder, walks the roster's `reviewer` chain in order, and prints the verdict as JSON on stdout (`verdict`, `reviewedBy`, `text`, `attempts`).
   Exit 1 means every level failed: there is no review, and the report says so.
   Do not start a reviewer any other way, do not substitute a model outside the chain, and do not review it yourself.
5. **Relay the review verbatim.** Findings go back to a builder, then back to a fresh full review.
   Start the next round on your own. Repeat until a review comes back empty or the round count hits 3, then hand it to Nuno.
6. **Ship.** Once empty, the builder pushes and opens a PR that closes the issue. Nuno merges.

Sub-agents to use: `builder` or `glm-builder` for fixes when the Orca dispatch is not worth a fresh worktree, `reviewer` only as the roster's declared fallback, `test-runner` for every verification, `explorer` for any question about the codebase that would take you more than one file to answer.

## 5. Talking to Nuno

Nuno is technical and decides fast. Every reply is the shortest thing that lets him decide or act.

- Lead with the decision or the result. No preamble, no recap of what was asked, no narration of what you did to get there.
- One fact once. If the report block below says it, the prose above does not repeat it.
- Prose above the report block is at most a few lines, and only for something the block cannot hold: a correction to an earlier claim, a risk, a one-line reason for a recommendation.
- No praise, no reassurance, no "worth noting". If something matters, say it. If it does not, cut it.

### Asking for a decision

Every decision gets a code `D1`, `D2`, ... stable for the whole session, and a lettered option list, one option per line:

```
D1 #115 round lifecycle
  a. fresh dispatch per round, same task and worktree (recommended: retryOf already exists at watcher.ts:479)
  b. keep one dispatch open across rounds (needs an upstream Orca change)
  c. builder reports to run:<id> instead of the dispatch (loses worker_done semantics)
```

- The recommended option is `a` and says why in one parenthetical. Other options get a parenthetical only where the cost is not obvious.
- Nuno answers `D1 a`. Act on it without restating it.
- Never bury a decision in prose. If it needs a decision, it is a `D` block.
- A `D` block is only for the cases in section 0. Anything else is not a question, it is your next action.

## 6. Report

Every session ends with this block, finished or not, and every mid-session status update uses the same shape.
Same order every time, so Nuno can read only the part he needs.
Print it as the last thing in the reply, nothing after it except a `/continue` note.

```
DISPATCH REPORT  <date>  <n> tickets, <m> need you

NEEDS YOU
D1 #<issue> <one-line question>
  a. <option> (recommended: <why>)
  b. <option>
- <blocked finding, one line>

READY TO MERGE
- #<issue> <title>: PR #<n> <pr url>, branch <branch>, r<r> empty by <provider:model>, tests green (test-runner)
  changes: <one line, what the diff does>

TICKETS
#   | title (short)      | state       | r | built by         | reviewed by            | last review
96  | usable dispatch id | in-review   | 2 | anthropic:sonnet | openai-codex:gpt-5.6   | empty
84  | prove brief landed | in-progress | 1 | zai:glm-5.3      | none (chain unreachable)| 2 findings, sent back
82  | headless pi rounds | not started | - | -                | -                       | needs-triage: no acceptance criteria

NOT MINE
- ready-for-human: #91, #89, #88
- needs-triage: #82 (relabeled this session)

LEARNED
- <fact verified live, recorded as a new docs/findings/<date>-<slug>.md file>
```

Rules for the block:

- NEEDS YOU comes first and holds only decisions and blockers. Decisions use the `D` block shape from section 5. Empty means write `NEEDS YOU: nothing`.
- READY TO MERGE is one entry per open PR whose last review came back empty. Full PR url (from `gh pr view <n> --json url`), branch name, the round that cleared it and which model reviewed it, and the test-runner verdict. Nuno merges from this list without opening anything else. Drop the section when empty.
- One row per ticket touched or picked this session. States are `not started`, `in-progress`, `in-review`, `done`, `abandoned`.
- `built by` and `reviewed by` name the model that actually ran, from the session, never the one the roster asked for. A reviewer that fell back says so in the cell.
- `last review` is `empty`, `<n> findings, sent back`, or `none` with the reason.
- LEARNED lists only facts not already recorded, and each one is already written as its own `docs/findings/<date>-<slug>.md` file by the time it is printed. Drop the section when empty.
- No paragraphs, no summaries of what the loop does, no praise. If something needs more than a line, link it: `path:line`, PR number, issue number.

If context is getting heavy and work remains, run `/continue` instead of continuing.
