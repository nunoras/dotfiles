# Example Review

User asks: "Review the back and forth I just had after using this skill. Can we enhance the skill so this is handled automatically?"

Expected response:

```markdown
## Skill improvement review

**Target skill/workflow:** slide-cleanup  (`~/.claude/skills/slide-cleanup/SKILL.md`)

**What happened:**
You had to ask twice for the skill to preserve speaker notes and keep the source citation slide.

**What the skill should handle automatically next time:**
1. Always preserve speaker notes unless the user asks to remove them.
2. Before deleting appendix or citation slides, ask for confirmation.

**Recommended skill updates:**
| Area | Change | Why |
|---|---|---|
| workflow | Add a preservation pass before editing slides. | User had to correct deleted notes. |
| guardrail | Require confirmation before deleting citation/appendix slides. | User expected those slides to stay. |

**Proposed patch:**
```diff
--- a/SKILL.md
+++ b/SKILL.md
@@ ## Core behavior
+## Preservation checks
+- Preserve speaker notes unless the user asks to remove them.
+- Confirm before deleting citation or appendix slides.
```

**Question for you:**
Approve this update, adjust it, or skip it?
```

After approval, apply the Edit, bump `slide-cleanup`'s `version`, and append an entry to this skill's `CHANGELOG.md`.
