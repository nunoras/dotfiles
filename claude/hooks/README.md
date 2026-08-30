# Claude Code hooks

Hooks are wired in [`../settings.json`](../settings.json) and linked into
`~/.claude/hooks/` **file by file** by `install.ps1` - not as a whole directory,
so hooks that other tools drop in there (plugin self-healers and the like) are
left untouched.

Hook commands run through Git Bash on Windows, so paths in `settings.json` use
`$HOME/...` rather than a hardcoded `C:\Users\<me>\...`.
That keeps one `settings.json` working on machines with different usernames.


## unslop (`unslop-always.ps1`)

A `SessionStart` hook that prints the body of `ai/skills/unslop/SKILL.md` to
stdout, which Claude Code adds to the session context.

It exists because a skill can't declare itself always-on. Claude Code loads a
skill's `name` and `description` at startup and leaves the body on disk until
the model decides to invoke it. Unslop's description says "Must always apply",
but that's prose in a YAML field, not something the harness enforces, and the
failure is silent: you never see a skipped invocation, only worse writing. The
frontmatter has no always-on field, just `disable-model-invocation` and `paths`,
which both narrow auto-loading rather than widen it.

Costs about 1,700 tokens per session, paid even in sessions that only touch
code. Drop the `settings.json` entry if that stops being worth it - the skill
still works as `/unslop`.

It strips the YAML frontmatter before printing, since the skill listing already
carries the name and description. If the skill file is missing it exits 0 and
prints nothing. It resolves the skill through `$HOME\.claude\skills\` rather
than `$PSScriptRoot`, because this file is a symlink and walking to a sibling
directory from the link would land in the wrong tree.
