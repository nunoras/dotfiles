---
name: sketch
description: Build a design sketch as one HTML board, the page on the right and the open decisions on the left, so the user can switch options and see each one take effect. Use when a design choice (a screen, a section, an interaction, a layout) goes to the user as options, or when the user asks for a sketch or a mockup.
---

# Sketch

A sketch is one HTML file built from `board.html` in this folder.
The right side shows one slide at a time: the screen or state a decision changes.
The left side lists each open decision as a code and its option letters.
Clicking a decision or a letter shows that decision's slide and scrolls to the part it changes.
A letter changes the page at once, with no outline or tag, so the user compares options by switching between them.
The page scrolls only when the part that changed is off screen.
The top bar shows the focused decision: the picked option, its label, and its pro and con.
On a phone the left side becomes a bottom strip: swipe for the next decision, tap a letter.

## Build one

1. Look at 2 or 3 real products that solve the same problem.
   Then draw the part that changes at real size, in the app's own colors, type and spacing.
2. Copy `board.html` to a new folder for the sketch, named for the decision, such as `~/sketches/credits-notice/index.html`.
   Never write a sketch into `/tmp` or a repo root.
3. Replace the JSON in `<script id="sketch-config">`:
   - `title`: the page title.
   - `viewport`: `null` to fill the right side, or `{"width":390,"height":844}` for a fixed screen such as a phone.
   - `decisions`: one entry per decision, in the order the user should take them.
     Each has `id` (`O1`, `O2`, ...), `q` (the question in a few words), `rec` (the recommended option letter) and `options`.
     Each option has `k` (`A`, `B`, ...), `label` (two to four words) and `pc` (one pro and one con).
     Keep codes stable for the whole conversation; a new decision gets the next free number.
4. Replace the contents of `<template id="sketch-page">` with the page: its own `<style>` and its markup.
   It renders in an iframe, so its CSS never touches the board.
   Build the whole page or section, not a fragment, so each option is seen in place.
   Split it into slides: wrap each screen or state in an element with `data-slide="O1 O2"`, naming every decision it shows.
   One slide per decision is the default; a slide may serve several decisions that change the same screen.
   Never put `data-when` on a slide element itself.
   A board with no `data-slide` shows everything at once.
5. Wire each option into the page:
   - `data-when="O3=A"` shows an element only for that option.
     `O3=A,B` matches either; `O3=A O4=B` needs both.
   - The iframe's `<html>` carries `data-o3="A"` for every decision, so CSS can change a style per option: `[data-o4=B] .notice{background:#fbeedd}`.
   - `data-touch="O4"` marks an element a CSS rule changes, so the slide scrolls to it when `O4` is picked.
     Elements with `data-when` are found without it.
6. Serve the folder with `sketch.mjs` from this folder so it outlives the session, and share it on the tailnet:
   ```
   systemd-run --user --unit=sketch-<name> node <this folder>/sketch.mjs serve <folder> <port>
   tailscale serve --bg --https=<tailnet port> http://localhost:<port>
   ```
   A plain static server shows the board, but only `sketch.mjs` receives the picks.
   Off Linux, use the platform's own user service.
   Read `tailscale serve status` first, and do not reuse a port or path it lists.
   Get the host with `tailscale status --json | jq -r .Self.DNSName`.
   Open `https://<host>:<tailnet port>/` yourself, then send it, never a localhost or file URL.
   The board reloads by itself when you edit the file, and keeps the user's picks.
   Never ask the user to refresh.
   The picks live in the URL hash: `https://<host>:<tailnet port>/#O3=C&at=O3` opens with `O3-C` on and `O3` in view.
   Send such a link to point the user at one option.
7. Screenshot it headless and look before you send it:
   ```
   chromium --headless=new --disable-gpu --hide-scrollbars --window-size=1400,900 --virtual-time-budget=2000 --screenshot=<png> http://localhost:<port>/
   ```
   On Windows, or for a fixed or phone viewport, do not use `--window-size`.
   Capture through a CDP harness (`msedge` on Windows) that sets device metrics and touch emulation.
   Capture one option with its hash URL, such as `http://localhost:<port>/#O3=C&at=O3`.
   A red "Sketch error" in the top bar means one of two things.
   A `data-when`, `data-touch`, `data-slide`, `rec` or `locked` names a decision or option that does not exist.
   Or two options of one decision "look the same": neither has a `data-when` or a CSS rule, so the letters change nothing.
   Only one option of a decision can be the page as it is.
   Render the recommended option of every decision at least once.

## Taking picks back

After you send the board URL, wait for the picks with a background command, so its exit wakes you:

```
node <this folder>/sketch.mjs wait <port>
```

It prints the picks and exits when the user presses Send picks or locks the last open decision.
If it stops with no picks, do not start it again.
When the user says the picks are sent, run it once more; it returns at once.
Do not also ask through a question tool.

The picks are a line such as `Locked: O3-B. Leaning: O4-A.`
Send picks also copies that line, so the user may paste it instead.
For each locked decision, add `"locked":"B"` to its entry in the config.
A decision with `locked` in the file stays locked in every browser and drops out of the left menu.
Leaning picks are not decisions; ask about them or keep them open.
A pick that comes with a caveat becomes a new option on the board.
Nothing outside the board changes until the decision is locked.

When the user changes an option rather than picking one, edit that option or add a new letter, and keep the other codes.
When a new question comes up, add it as a new decision on the same board rather than starting a new file.

## The board stays minimal

The left menu shows only the code, the question and the letters.
Labels, pros and cons live in the hover tooltip and in the top bar, which shows one decision at a time.
Do not add text, headers or help to the menu; the user chose it this bare.

## In a repo with its own capture recipe

When a repo has a way to capture its real CSS and DOM, such as MyApp's control-app "Sketch from the live app", use that capture as the page inside `sketch-page` and edit only the parts the decisions change.
