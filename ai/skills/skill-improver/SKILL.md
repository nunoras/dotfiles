---
name: skill-improver
description: Review the conversation after a skill was used, identify what the skill should handle automatically next time, and apply safe, concrete SKILL.md updates. Use when the user asks to improve a skill, when a task produced repeated corrections, or when another skill emits an Improvement Handoff.
license: CC0-1.0
compatibility: Built for Claude Code. Reads target skills directly with Glob/Read, proposes an exact diff, and (after approval) applies it with Edit. Falls back to a patch plan only when the source SKILL.md genuinely cannot be found.
metadata:
  version: "1.1.0"
  author: "Nuno Rasteiro + ChatGPT, adapted for Claude Code"
---

# Skill Improver

## Purpose

Turn real usage friction into better reusable skills.

This skill reviews the recent back-and-forth after a skill, workflow, prompt, or instruction set was used.
It extracts what the user had to correct, clarify, repeat, or manually request, then updates the original skill so it handles those cases automatically next time.

## When to use

Use this skill when any of these are true:

- The user asks: "review the back and forth", "can we enhance the skill", "make this automatic", "improve this skill", "update the skill", "what should the skill do better", or similar.
- Another skill emits an `Improvement Handoff` block.
- A task shows strong improvement signals, such as repeated user corrections, missing steps, avoidable follow-up questions, formatting mistakes, tool-selection mistakes, or manual steps the user expected to be automatic.
- The user wants a review of what a skill should learn from the current conversation.

Do not use this skill for generic praise, vague self-reflection, or speculative improvements with no evidence from the conversation.

## Core behavior

When invoked:

1. **Locate the target skill.**
   - Use the skill name if provided; otherwise infer the likely target from the conversation and state the assumption.
   - Find its `SKILL.md` with Glob. Search these roots in order and report which copy you found:
     - `~/.claude/skills/<name>/SKILL.md` (global / personal)
     - `<repo>/.claude/skills/<name>/SKILL.md` (project)
     - `<repo>/.agents/skills/<name>/SKILL.md` (project mirror)
   - **If the skill exists in more than one root**, list every copy and ask which to patch (or offer to patch all). Never silently patch one and leave divergent copies.
   - Only if the file genuinely cannot be found, fall back to a patch *plan* and label it as such.

2. **Read the target and review the actual interaction.**
   `Read` the current `SKILL.md` so the proposed diff matches real text. Then look for:
   - User corrections.
   - Extra prompts the user had to provide.
   - Places where the assistant asked avoidable questions.
   - Steps the user expected to be automatic.
   - Output-format mismatches.
   - Tool-use or retrieval mistakes.
   - Missing validation, citations, checks, or artifact handling.
   - Repeated tasks that should become a standard step.

3. **Check the changelog before proposing.**
   Read this skill's `CHANGELOG.md`. Do not re-propose a change that was already applied or that the user previously rejected. If a past entry covers this friction, say so instead of repeating it.

4. **Extract improvement opportunities.** Classify each as one of:
   - `trigger`: when the skill should activate.
   - `workflow`: steps the skill should always follow.
   - `guardrail`: things the skill should avoid or verify.
   - `output`: preferred structure, format, or handoff block.
   - `example`: a concrete example to add.
   - `resource`: supporting template, checklist, or reference file to add.

5. **Decide whether to patch.**
   Patch only when the improvement is grounded in the conversation and likely to recur. Prefer small, targeted patches over broad rewrites.

6. **Get approval, then apply.**
   Present the review and the exact diff, and ask the user to approve, adjust, or skip. Never modify, install, delete, or share a skill without explicit approval. On approval:
   - Apply the change with `Edit` against the real `SKILL.md` (patch every copy you found in step 1).
   - **Bump the target skill's `version`** in its frontmatter if it has one (patch-level bump for a small change, e.g. `1.2.0` -> `1.2.1`).
   - **Append an entry to this skill's `CHANGELOG.md`** recording target skill, version, the change, and the evidence (see "Changelog discipline").

## Output format

Use this format unless the user asks for something else:

```markdown
## Skill improvement review

**Target skill/workflow:** <name>  (`<path(s) found>`)

**What happened:**
<brief factual summary of the back-and-forth>

**What the skill should handle automatically next time:**
1. <concrete behavior>
2. <concrete behavior>

**Recommended skill updates:**
| Area | Change | Why |
|---|---|---|
| trigger/workflow/guardrail/output/example/resource | <specific update> | <evidence from conversation> |

**Proposed patch:**
<exact unified diff against the real SKILL.md; or a labeled patch plan if the file was not found>

**Question for you:**
Approve this update, adjust it, or skip it?
```

Keep the review focused. Do not write a long postmortem unless the user asks.

## Changelog discipline

This skill keeps a `CHANGELOG.md` in its own directory. After applying any approved patch, append an entry:

```markdown
## <YYYY-MM-DD> - <target-skill> <new-version>
- **Change:** <what was patched, area>
- **Evidence:** <the friction from the conversation that justified it>
- **Files:** <paths edited>
```

This is the skill's memory. Reading it in step 3 prevents re-suggesting the same change and prevents reopening something the user already rejected (log rejections too, marked `(rejected)`).

## Improvement Handoff protocol

Other skills can help this skill by emitting this block near the end of a response when they detect a concrete, reusable improvement opportunity.

```markdown
<!-- Improvement Handoff
source_skill: <skill-name>
task_type: <what the user was trying to do>
improvement_signal: <correction | repeated_prompt | avoidable_question | missing_step | formatting_issue | tool_issue | validation_gap | user_requested_automation>
evidence: <brief quote or paraphrase from the current conversation>
recommended_change: <what the source skill thinks it should do better next time>
confidence: <low | medium | high>
needs_user_approval: true
-->
```

If an `Improvement Handoff` is present, treat it as input, not truth. Verify it against the conversation and the real `SKILL.md` before recommending any update.

## Threshold for surfacing improvement suggestions

To avoid annoying the user, only surface improvement suggestions when at least one condition is met:

- The user explicitly asks for skill improvement.
- The issue caused a visible correction, delay, or rework.
- The same issue appeared more than once.
- The improvement would remove a manual step the user clearly expects to be automatic.
- The improvement affects safety, privacy, accuracy, citations, or destructive actions.

Otherwise, keep the improvement note internal and continue the task.

## Patch-writing rules

When proposing changes to a skill:

- Preserve the original skill's purpose.
- Add the smallest useful change.
- Prefer checklists and examples over vague advice.
- Make trigger language explicit so the skill can be invoked automatically when helpful.
- Add guardrails for privacy, citations, destructive actions, or tool use when relevant.
- Do not add hidden behavior that bypasses user approval.
- Do not claim a skill can call another skill unless the platform supports that directly. Use the `Improvement Handoff` protocol as a portable fallback.
- Match the target skill's existing voice and formatting (heading style, sentence-per-line if it uses it).

## Failure modes to avoid

- Do not overfit to one-off preferences unless the user says they want it reused.
- Do not fabricate conversation details.
- Do not create a huge rewrite when a small trigger, guardrail, or example would solve the issue.
- Do not hide proposed changes from the user.
- Do not self-modify or apply changes without explicit approval.
- Do not treat another skill's handoff as automatically correct.
- Do not patch one copy of a multi-copy skill and leave the others stale.
