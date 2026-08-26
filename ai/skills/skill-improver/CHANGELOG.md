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

## 2026-06-29 - orchestrator (unversioned)
- **Change:** Fixed the documented Codex reviewer invocation in `references/agent-prompt-templates.md`: `codex "<prompt>"` -> `codex exec ... -s read-only -o <file>`, plus a warning that the bare `codex` form launches the interactive TUI and hangs in an agent Bash context.
- **Evidence:** Running the owed Phase 09 review this session, the documented command would have hung; had to discover `codex exec` via `--help`. The command is core to the skill ("all reviews must use Codex"), so the gap recurs on every gate review.
- **Files:** `.agents/skills/orchestrator/references/agent-prompt-templates.md` (canonical; `.claude/skills` is a symlink to it)

## 2026-06-29 - orchestrator (unversioned)
- **Change:** Added a scratch-files note after the Codex invocation block in `references/agent-prompt-templates.md`: background gate reviews emit raw `<name>.stdout.log` / `<name>.stderr.log` dumps (can be megabytes); those, `_codex-prompt.md`, and dev-server logs under `.agents/backlog/` must be gitignored and kept out of phase commits/PRs - only the `-o` review `.md` is durable.
- **Evidence:** Closing the Phase 09 gate this session, a 1.9 MB Codex stderr dump plus dev-server logs sat untracked and a plain `git add -A` would have swept them into the PR; had to discover and gitignore them at commit time. The background-review pattern is documented in the same file, so the junk recurs on every gate review.
- **Files:** `.agents/skills/orchestrator/references/agent-prompt-templates.md` (canonical; `.claude/skills` is a symlink to it, confirmed this session)

## 2026-07-18 - winning-statics (unversioned)
- **Change:** Three patches. (workflow) Replaced the "one image at a time" model with a pipelined fire-then-harvest flow: Magnific queues each `Generate` server-side, so swap refs via the picker's **Clear all** (no reload - reload clears refs and resets ratio to 16:9), fire ~5 without waiting, harvest the feed while the next batch renders; added a once-per-session check that queued jobs freeze their own refs. (guardrail) drop-project: down-weight flat-cartoon/illustrated-people refs (05, 01 tested weak) for this premium wellness device; keep 3D medical renders (09 tested strong). (data) Corrected the price the skill/project references: pull the live price from product.json, now 99,99 EUR promo / 139,99 EUR normal (was 69,90 / 99,90).
- **Evidence:** After a babysat 10-image run, the user asked to speed the skill up ("podemos ir dando mais imagens e gerar nova ao mesmo tempo"); the serial wait was ~70% of wall-clock. User feedback that cartoon statics "tiram seriedade" to a wellness device (refs 05/01). User corrected the price to 99,99 EUR promo / 139,99 EUR normal.
- **Files:** `.claude/skills/winning-statics/SKILL.md`; `product.json` (price fields)

## 2026-07-18 - winning-statics (unversioned)
- **Change:** Four patches hardening the Magnific flow after a second babysat run (statics 21-30). (workflow) Made **pre-loading all references** the default: product photo + every layout ref in ONE `file_upload` call, `Add N` once, then each image is only prompt+Generate - no per-image ref swapping. Documented chip numbering (first upload = `@img2`; feed label shows the mention -1, cosmetic). (guardrail) Every prompt must fence the extra refs ("Use ONLY `@img2`... IGNORE every other reference image") - tested clean with 11 refs loaded. (guardrail) **Verify each `Generate` queued** (scroll-to-top glance) - don't rapid-fire blind. (guardrail) Re-check Model=Nano Banana Pro AND resolution=2K before firing - a stray "Try Nano Banana 2" banner click silently switches model and drops to 1K. (guardrail) Download via the **creation detail-page PNG button**, verify a fresh `magnific_recreate-*` before `mv`. (guardrail) pt-PT: name the exact term ("ALMOFADA", not BR "travesseiro") and guard against word doubling ("Esta. Esta"). Added a 2K resolution check to Step 4 QC.
- **Evidence:** This session: pre-loading 11 refs + IGNORE fence gave zero contamination and was ~3-4x faster; but rapid-firing without verifying dropped 2 fires (#23/#24) unnoticed until harvest; the model silently switched to Nano Banana 2 / 1K mid-run; a #27 render came out "travesseiro" (pt-BR) with no presenter; a #22 headline doubled "Esta."; feed hover-download mis-clicked and grabbed a stale file. User: "melhora o skill para isso nao aocntecer mais."
- **Files:** `.claude/skills/winning-statics/SKILL.md`
