---
name: yf-status
description: Use when you want a quick read-only glance at yf-plan progress - how many phases are done, which phase is active, what is next, and any failures - across all plans in specs/ or for one plan. Triggers - "plan status", "where are we", "what's next", progress, which phase is active.
---

# YF Status

Read-only glance at yf-plan progress.
No agents and no writes - just parse the status markers in the plan HTML and print a compact table.
Default scope is every plan in `specs/`.

## When to use

- "Where are we on the plans?" or "what's next?"
- A quick check before picking up or resuming work.

Not this skill: running a plan (`yf-run`) or editing it (`yf-plan`).

## What it reads

Each phase is an `<h3>` in the plan carrying a status marker: `[]` idle, `[wip]` in progress, `[x]` done, `[f]` failed.
yf-status counts these - it never changes them.
It looks only at phase-level markers; per-task checklist markers are ignored for the summary.

## The Loop

1. **Collect plans.** Default: all `specs/*.html`. If a plan path or name is given, use just that one.
2. **Parse phase headers.** For each plan, grep the phase headers and read each marker + name, e.g. `<h3><code class="status">[x]</code> Phase 2: Data model</h3>`. A working pattern: `class="status">\[[^]]*\]</code> Phase`.
3. **Compute per plan:** phases done (`[x]`) over total, the active phase (first not `[x]`), any `[f]` phases, and the next action.
4. **Print** one compact row per plan.

## Next action rule

- Any `[f]` present - flag the plan with a trailing ` !` and list the failed phase(s) under the table.
- All phases `[x]` - next is `ship: /yf-ship <name>`.
- Otherwise - `/yf-run <name>` to continue at the active phase.

## Output shape

```text
PLAN                       PHASES   ACTIVE             NEXT
brain-split-brief-view     3/5      Phase 4: Wiring    /yf-run brain-split-brief-view  (Phase 4)
usage-monitor              5/5      done               /yf-ship usage-monitor
drop-spawn-animation       0/3      not started        /yf-run drop-spawn-animation  (Phase 1)
```

Keep it text - no artifact, no agents. This skill should stay cheap enough to run any time.
