---
name: note
description: "Capture one fact, decision or idea into the repo's .brain inbox, fast and unjudged. Use when something worth keeping past this task has just been established - an engine fact paid for dearly, a direction decided, an idea parked - or on \"note that\", \"put that in the brain\", \"keep that\"."
---

# Note

Capture, and nothing else.

Read `~/.claude/brain/conventions.md` first.

This skill is deliberately cheap.
It does not read the other notes, does not dedupe, does not reorganise, and does not judge whether the note is well written.
Duplicates are fine - `/meditate` merges them.
The only thing that must not happen is a note being lost because writing it felt like a detour.

## 1. Check there is a `.brain`

No `.brain` in the repo root: say so, name `/brain-init`, and stop.
Do not create the folder as a side effect.

## 2. Decide whether it belongs here at all

Apply the three-month test from the conventions.

If the thing is a task-record - what was built this session, what broke, what was fixed - refuse it and route it per the conventions.
Say which it is and stop.
Do not write the note anyway "just in case".

If it is something the code already says, refuse it the same way and name the file that says it.

## 3. Write it

One file in `.brain/inbox/`, kebab-case, `.md`.

Frontmatter with `updated` and `topics`.
Take `topics` from the vocabulary in `.brain/README.md`; if none fits, use the closest and let `/meditate` sort it out.

The body carries:

- **what is being claimed**, in the repo's language, one sentence per line.
- **the status of each claim** - verified, probable, undecided - marked inline in the repo's language.
- **the proof**, next to any verified claim: file and line, the query, the thing seen in-app. A verified claim with no proof beside it is a probable claim wearing a badge.
- **where it came from**, if that is short: the issue number, the session's subject. One line.

Do not pad it into a document.
Three sentences with a file:line is a complete note.

## 4. Report

One line: the path written, and the topics.

If anything was refused, say what and where it should go instead.
