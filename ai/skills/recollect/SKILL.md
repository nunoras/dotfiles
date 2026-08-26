---
name: recollect
description: "Read the repo's .brain whole and hand back what is in it - a digest led by open ideas and undecided calls, or a targeted read when given a topic. Use on \"what's in the brain\", \"recollect\", \"what did we decide about X\", or to prime a session with the project's established facts before starting work."
---

# Recollect

Read `~/.claude/brain/conventions.md` first.

There is no index.
Read the notes themselves, every time.
An index would be a second source of truth, and a stale index reports a `.brain` that no longer exists - confident wrong recall is the one failure that destroys trust in the whole store.

Read the curated folders - `facts/`, `direction/`, `ideas/`, `reference/`.
Read `inbox/` only for its depth, not its content: it is staging, and reporting it as knowledge defeats the point of having it.

## Bare form: the digest

Group by **topic**, not by folder.
Folders are how a note is filed; topics are how the user thinks about the project.

Lead with what the user **cannot see by looking at the folder**:

1. **Open ideas.** Everything in `ideas/`, plus anything elsewhere marked undecided. This is the whole reason the digest exists - parked ideas are exactly what gets forgotten.
2. **Probable, not yet verified.** Claims marked probable, with what each one is still missing. These are the cheap wins.
3. **Decided.** One line each, so the settled direction is visible without being re-litigated.
4. **Established facts.** Grouped by topic, one line each, with the proof's location. Do not restate the facts in full - the point is knowing they exist and where.

Close with the nudge, and only if there is something to nudge about:

- how many notes are sitting in `inbox/`
- how many notes have not been touched in over three months

Do not editorialise or propose changes.
That is `/meditate`, and mixing the two means the user reads neither.

## With a topic: the targeted read

`/recollect <topic>` answers a question against `.brain`.

Match the topic against the frontmatter `topics`, the subfolder names, and the note titles - in that order, and do not stop at the first hit.
Read every note that matches, whole.

Answer the question directly, then cite the notes the answer came from by path.
Say plainly when `.brain` does not cover it, rather than reasoning from the code and presenting it as a recollection.
A confident answer assembled from somewhere other than `.brain` is the failure this skill exists to avoid.

## When there is no `.brain`

Say so, name `/brain-init`, and stop.
