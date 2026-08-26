# Pane orchestration - tickets

Local-markdown tracker for the [pane orchestration spec](../../pane-orchestration-spec.md).
No GitHub/Linear tracker is wired up, so tickets live here as one `.md` each.

Each ticket has frontmatter: `id`, `title`, `status` (open | claimed | done), `blocked_by`.
Claim a ticket by setting `status: claimed` before working it.

## Order

Research is done; these are build tickets.

| id | title | blocked by |
|---|---|---|
| 01 | Roster config + harness-derivation helper | - |
| 02 | Authenticate openai-codex in pi (or default reviewer to OpenRouter) | - |
| 03 | dispatch.ps1 - frontmatter-driven pane dispatch | 01 |
| 04 | Extend herdr-autostart for arbitrary provider+model+fallback | 01 |
| 05 | Fallback watcher - relaunch dead session on fallback model | 03, 04 |
| 06 | review.ps1 - split-right read-only pi reviewer | 03, 04 |
| 07 | Local to-tickets override that stamps roster frontmatter | 01 |
| 08 | Uninstall /workflows and scrub references | - |
| 09 | Update README-glm.md and AGENTS.md | 03, 06, 08 |

## Roster (source of truth)

| role | harness | primary | fallback |
|---|---|---|---|
| planner | Claude Code | `claude-fable-5` | `claude-opus-5`, then manual restart on pi |
| builder A | pi | `zai:glm-5.3` | `openrouter:z-ai/glm-5.2:free` |
| builder B | pi | `openrouter:stealth/ox-alpha` | `openrouter:z-ai/glm-5.2:free` |
| reviewer | pi | `openai-codex:gpt-5.5` | none - fail loudly, then the Opus `reviewer` agent by hand |

The OpenRouter account is free-tier with no credits, so fallbacks name `:free` ids only.
A paid id passes `pi auth check` and then dies mid-session with a 402.

Harness is derived from provider: `anthropic` -> Claude Code, everything else -> pi.
Models are written `provider:id` because `pi --model provider/id` silently mis-resolves; dispatch splits this into `--provider <p> --model <id>`.
