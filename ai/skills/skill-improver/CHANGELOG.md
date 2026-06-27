# skill-improver changelog

This is the skill's memory of every improvement it has applied to other skills.
Read it before proposing changes so the same suggestion is never made twice, and log rejected suggestions too (marked `(rejected)`) so they are not reopened.

Format per entry:

```
## <YYYY-MM-DD> - <target-skill> <new-version>
- **Change:** <what was patched, area>
- **Evidence:** <the friction that justified it>
- **Files:** <paths edited>
```

---

## 2026-06-27 - skill-improver 1.1.0 (self)
- **Change:** Adapted the imported v1.0.0 skill for Claude Code: locate skills via Glob across global/project/mirror roots, read the real SKILL.md, propose exact diffs, apply with Edit after approval, bump target version, and keep this changelog. Added a multi-copy guardrail.
- **Evidence:** Original was written for generic ChatGPT/Agent Skills and defaulted to "patch plan" hedging that is dead weight when files are directly readable.
- **Files:** SKILL.md, references/patch-template.md, examples/review-example.md, CHANGELOG.md (new)
