# Skill Patch Template

In Claude Code the target `SKILL.md` is almost always readable, so the "Proposed patch" should be an exact unified diff against the real file (the kind you can apply with Edit), not a vague plan.

```markdown
## Skill improvement review

**Target skill/workflow:** <name>  (`<path(s) found>`)

**What happened:**
<brief factual summary>

**What the skill should handle automatically next time:**
1. <behavior>
2. <behavior>

**Recommended skill updates:**
| Area | Change | Why |
|---|---|---|
| <area> | <specific update> | <conversation evidence> |

**Proposed patch:**
```diff
--- a/SKILL.md
+++ b/SKILL.md
@@
-<old line>
+<new line>
```

**Question for you:**
Approve this update, adjust it, or skip it?
```

After approval: apply with Edit, bump the target skill's `version`, and log the change in this skill's `CHANGELOG.md`.

Use a labeled patch *plan* (no diff) only when the source `SKILL.md` genuinely cannot be found.
