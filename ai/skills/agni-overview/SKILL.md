---
name: agni-overview
description: Show every active agni task, or only the current project's with "here", as a live status card in T3 Code, and post a fresh card each time a task changes state. Use when the user asks for an "agni overview", "agni overview here", "agni dashboard", "what is agni doing", or to see all running agni tasks at once.
---

# agni overview

1. Run `node "$HOME/.claude/scripts/agni-overview.mjs"` from the project directory, so tasks from that project drop the project label.
   For "agni overview here", add `--here`: the card then shows only the project this session is in, and the watcher posts a new card only when one of its tasks changes.
2. Pass its stdout unchanged to `html_render` with title `agni overview` and height `2000`.
   Do not restate the card in the reply.
3. That run also turns on overview mode for this session, and the `agni-watch` hook asks you to arm the watcher.
   Arm it.
   Each time the watcher returns `t3: overview` or `t3: overview --here`, repeat steps 1 and 2 with the flags that line names.
   Running the script again with or without `--here` switches the scope.

A T3 card cannot refresh itself.
Its frame cannot reach this machine, and sending task titles to a public URL would publish private work.
So each change posts a new card, and older cards keep their "as of" time.

To stop, run `node "$HOME/.claude/scripts/agni-overview.mjs" --off`.
The watcher stops at its next return unless it is still watching tasks approved in this session.

Without T3 Code tools, run `agni status --active` and give a short table instead.
