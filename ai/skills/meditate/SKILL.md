---
name: meditate
description: "Audit the repo's .brain - empty the inbox into the folders, fix what is mechanical, and propose every judgement call. Use on \"meditate\", \"audit the brain\", \"clean up .brain\", or when the inbox has grown and the notes need gardening."
---

# Meditate

The gardening pass.
Capture is deliberately cheap, which makes this skill the thing that keeps `.brain` worth reading.

Read `~/.claude/brain/conventions.md` first.
Read `.brain/README.md` for this repo's topic vocabulary, language and exceptions.
Then read every note, whole, including `inbox/`.

## The split that governs everything here

**Mechanical fixes apply directly.** They are verifiable and boring, and making the user approve thirty of them means they stop reading at number thirty-one.

**Judgement calls are proposed and wait.** They are the actual product. A wrong deletion here is unrecoverable knowledge, not a revertable code change.

Never blur the two.
When unsure which side something falls on, it is a judgement call.

## 1. Empty the inbox

Every note in `inbox/` gets filed into `facts/`, `direction/`, `ideas/` or `reference/`, by its primary purpose.

Filing is mechanical - do it, with `git mv`.
Merging is not: when an inbox note covers a subject an existing note already owns, **propose** the merge with both texts side by side and leave the inbox note where it is until the user answers.

## 2. Mechanical fixes - apply these

- Broken `related` / `supersedes` paths, and links to notes that moved.
- `updated` dates that contradict the note's own content or git history.
- `topics` naming something outside the README's vocabulary - map it to the closest, or flag the vocabulary as needing a new entry.
- Prose that is not one sentence per line.
- Folder names that drifted from the fixed vocabulary.
- Missing frontmatter on an otherwise fine note.

## 3. Judgement calls - propose these

Each one gets: the note, the evidence, and a recommendation. Then wait.

- **Shipped.** A note describing something that now exists. Cross-read `.brain` against `STATE.md` first - it is the repo's record of what got built and the cheapest high-signal source. When `STATE.md` is silent or ambiguous, check git history and the code before raising it. Attach whatever you found; never assert it shipped without evidence.
- **Overtaken.** A claim the code or the database now contradicts.
- **Stale probable.** A claim marked probable months ago that nobody ever confirmed. Propose either confirming it now or deleting it - a permanent maybe is noise.
- **Unproven verified.** A claim marked verified with no proof beside it. This is the most dangerous note in the store, because it will be trusted.
- **Duplicates.** Two notes on one subject. Propose the merge, and say which text survives where they disagree.
- **Fragments.** A note too thin to be useful on its own, better absorbed into a neighbour.
- **Wrong home.** A note that is really a task-record and belongs in `STATE.md`, or something the code already says.
- **Orphans.** A note nothing links to and no topic claims. Usually a missing link, occasionally a dead idea.
- **Thin folders.** A subfolder holding fewer than three notes - propose dissolving it back up a level.
- **Poorly written.** A note whose claim is real but whose text is vague, unstatused, or missing its proof. Propose a rewrite and show it; do not bulk-rewrite notes in place. A bulk rewrite is how the proof beside a verified claim quietly goes missing.

## 4. Report

Two sections, in this order:

**Applied** - the mechanical fixes, one line each.

**Proposals** - the judgement calls, numbered, each with its evidence and a recommendation.

Then stop and wait.
Apply only what the user picks.
