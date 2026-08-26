---
name: brain-init
description: "Set up .brain in a repo that does not have it, or bring an existing .brain onto the standard scheme. Use on \"init the brain\", \"set up .brain here\", or when /note or /recollect reports that the repo has no .brain."
---

# Brain init

Runs once per repo.

Read `~/.claude/brain/conventions.md` first - it holds the folder vocabulary, the note rules and the schema this skill writes.

## A: the repo has no `.brain`

1. **Settle the language.** Look at the repo's other prose - `README.md`, existing docs, commit messages. If it is not obvious, ask once. Folder names stay English regardless.

2. **Create the folders.** `inbox/`, `facts/`, `direction/`, `ideas/`, `reference/`. Each gets a `.gitkeep` so the empty ones survive a clone.

3. **Write `.brain/README.md`.** Everything the conventions say it must state, in the repo's language. Start the topic vocabulary empty and say so - topics get added as notes arrive, not invented up front.

4. **Report** what was created, and say that `/note` is now available.

Do not seed example notes.

## B: the repo already has a `.brain`

Never reorganise silently.
The value of the existing notes is entirely in someone having written them by hand, and a surprise bulk move is how that trust goes.

1. **Read every note, whole.** Titles alone are not enough to file by primary purpose.

2. **Detect the language and the de-facto topics** from what is already there. The existing folder names are usually the topic vocabulary already, just expressed as folders.

3. **Propose the migration.** A table: current path, proposed path, and the one-line reason. Group it by destination folder so it can be scanned. Call out separately:
   - notes that are genuinely both direction and fact, and the folder chosen for them
   - existing folders that become topics rather than folders
   - subfolders that survive because three or more notes want them
   - anything that fits nowhere, with the question it raises

4. **Wait.** Then apply what the user approves, with `git mv`.

5. **Write `.brain/README.md`** to match what actually landed, including the topic vocabulary the migration revealed and any exception the repo keeps.

6. **Add frontmatter** to migrated notes: `updated` from git history, `topics` from where the note came from. Do not rewrite the bodies - that is `/meditate`'s job, and only by proposal.

7. **Check the repo's agent instructions.** If `CLAUDE.md` or `AGENTS.md` documents the old scheme, it is now wrong. Propose the correction in the same breath - stale instructions in `CLAUDE.md` are worse than no migration, because every future session reads them.
