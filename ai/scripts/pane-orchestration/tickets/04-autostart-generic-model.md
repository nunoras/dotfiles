---
id: 04
title: Extend herdr-autostart for arbitrary provider+model+fallback
status: open
blocked_by: [01]
---

## Task

Teach `herdr-autostart.ps1` to start a pi session on an arbitrary provider+model with a fallback armed, driven by pane env.

## Detail

- Today autostart switches on `M2_AUTOSTART` in `{pi, claude, glm}`. Add a path that reads:
  - `M2_PROVIDER`, `M2_MODEL`, `M2_FALLBACK` (all `provider:id` form for the model refs).
- For the pi path, launch `pi -a --provider <p> --model <id>` (plus `--append-system-prompt` from the agent file if `M2_AUTOSTART_AGENT` is set).
- Do not try to pass fallback to pi (no CLI flag exists); the fallback env is recorded so the watcher (ticket 05) can relaunch on it.
- Stay PowerShell 5.1 compatible; clear the env vars before launch so a nested shell cannot relaunch.

## Done when

- Opening a pane with `M2_PROVIDER/M2_MODEL` set starts pi on exactly that model.
- The existing `pi` / `claude` / `glm` defaults still work unchanged.
