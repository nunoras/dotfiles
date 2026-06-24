# Pi config

Pi reads `AGENTS.md` natively (the "standard agents" approach), so its global
config should point at — or be — the canonical [`../ai/AGENTS.md`](../ai/AGENTS.md).

**TODO:** confirm where Pi stores its *global* config on Windows (candidates:
`~\.pi\`, `~\.config\pi\`, or an app data folder). Once known:

1. Drop the config file(s) in this folder, and
2. Uncomment the Pi line in [`../install.ps1`](../install.ps1) so it gets linked.

The COLLECT runbook will try to locate Pi's config automatically when run on a
machine that has Pi installed.
