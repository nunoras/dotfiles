---
name: setup-agni
description: Inspect this machine and recommend Agni profiles, role chains and caps. Use for a new setup or to review installed harnesses, available models and current configuration.
---

# Set up Agni

Inspect the machine, present a plan with exact commands, and make changes only after the user approves it.
Profiles support `claude` and `pi`; `codex` can run this skill but cannot back an Agni profile.
Never edit `config.toml` or `.agni.toml` directly, install or sign in to a harness, or install treehouse without an approved plan.

## Inspect

Finish inspection before proposing changes. These commands are read-only: `agni profile list`, `agni profile check`, `agni role list`, `agni role show`, and `agni treehouse install` without `--yes`.
Do not run `agni status` or `agni project` commands yet; they initialize Agni's state. Do not run `agni skill install` before approval because it writes to harness folders.

Run `<harness> --version` for `claude`, `codex` and `pi`. A printed version means installed. Report Codex as installed but unsupported for profiles; if it is the only installed harness, recommend no profiles.

Check sign-in with each installed harness: `claude auth status` (`loggedIn: true`), `codex login status`, and `pi auth check --provider <provider> --no-refresh` (`ready`). For pi, check each provider you may use. Treat unclear results as not confirmed. `agni profile check` may say `authenticated: unknown`; this still means the profile is ready, but sign-in is not confirmed.

Build an inventory of runnable models, each with an id, family and class:

- Pi: run `pi --offline --list-models`, then check each distinct provider. Only `ready` providers are runnable; report other catalogued models separately. Use `provider/model` ids. Let pi commands honor `PI_CODING_AGENT_DIR`; do not read pi's files.
- Claude: read `model` from `settings.json` in `$CLAUDE_CONFIG_DIR` or `%USERPROFILE%\.claude\settings.json`. Claude models belong to `anthropic`. If no id is configured, ask the user to provide one and propose no Claude profile.
- Codex: read `model` from `$CODEX_HOME/config.toml` or `%USERPROFILE%\.codex\config.toml`. Codex models belong to `openai`; this information is for the report only.

Classify ids from their tokens, not the provider prefix. Lowercase and split on non-alphanumeric characters; a token matches a marker when equal to it or followed by digits. Choose the first matching family in this order: `anthropic` (anthropic, claude, opus, sonnet, haiku), `openai` (openai, gpt, codex, o1, o3, o4), `xai` (xai, grok), `google` (google, gemini), `zai` (zai, zhipu, glm), `xiaomi` (xiaomi, mimo), `deepseek` (deepseek), `qwen` (qwen, tongyi, alibaba), `moonshot` (moonshot, kimi). For example, `opencode-go/mimo-v2.6-flash` is Xiaomi and `openrouter/anthropic/claude-...` is Anthropic. No match means unknown; do not guess.

Classify a model as workhorse when its tokens include `haiku`, `flash`, `mini`, `nano`, `lite`, `mimo` or `small`. Otherwise classify it as strong when it includes `opus` or `ultra`, a `gpt` token followed by version 5 or higher, or both `gemini` and `pro`. Leave other classes unknown.

Inspect existing profiles and role chains with `agni profile list`, `agni role list` and `agni role show <role>`. Run `agni treehouse install` as a preview. Count CPU cores and memory, and read `[caps]` from the machine config: `%LOCALAPPDATA%\agni\config.toml` on Windows or `~/.config/agni/config.toml` elsewhere, unless `AGNI_HOME` sets the Agni data directory.

## Recommend

Use workhorse models first for `build` and `fix`, and strong models first for `plan` and `review`. Base recommendations on runnable models, not harness count.

- For each family, propose profiles only for classes present in its runnable inventory. List unknown family or class entries as candidates, not recommendations. Profiles on an installed harness with unconfirmed sign-in may be proposed, labeled "not confirmed".
- Prefer a `review` chain whose strong model belongs to a different family from the `build` chain. Cross-family support depends on model families, not the number of harnesses. Name a missing family only when all runnable models share one.
- Use a profile-capable harness for every role it can serve. Name any class or family the inventory lacks.
- Suggest `caps.global` near half the CPU core count, bounded from 1 to 8, and `caps.project` of 1 or 2 when several projects run in parallel. Caps have no command; the user sets them in machine `config.toml`.
- If treehouse is missing or unsupported, include `agni treehouse install --yes` in the plan. Run it only after approval.
- Explain that every project needs a delivery policy and validation command. Include profiles, role chains, caps, gaps and the exact proposed commands in the plan.

After approval, install the bundled skills in installed harnesses and run `agni status`. Then check each registered project for a validation command.
Change nothing before approval.

## Apply

Run only approved commands and skip changes already present.

- `agni profile add <name> --harness <harness> --model <model> [--effort <effort>]` creates or updates a profile. Name it `<harness>-<family>-<class>` so reruns reuse it and profiles from different harnesses do not collide.
- `agni role set <role> --profiles <a,b>` sets a role chain; add `--project <project>` for a project-specific chain.
- `agni skill install --harness <harness>` installs or updates the bundled skills for that harness.
- Run `agni treehouse install --yes` only if it appeared in the approved plan.

### Projects

Agni will not dispatch tasks for a project without a validation command. Run `agni status`, then `agni project config get validation.command --project <name>` for each registered project. Leave existing commands alone.

For each missing command, inspect the repository and propose an appropriate check for its ecosystem (`Cargo.toml`, `package.json`, `pyproject.toml` or `go.mod`). Show the exact command and get approval before running `agni project config set validation.command "<command>" --project <name>`. If declined, report that the project remains paused and give the command to run later. Remind the user to commit `.agni.toml` so clones inherit the setting.

## Confirm

Check every profile with `agni profile check` and report `installed` and `authenticated` as printed. Treat only `true` as confirmed sign-in; `unknown` remains unconfirmed until the first session. Before setting role chains, use `agni profile list` to verify Agni's detected family matches each profile name. Confirm chains with `agni role list`, skills with the install output, and project pauses with `agni status`.

Report only what you ran and saw.
