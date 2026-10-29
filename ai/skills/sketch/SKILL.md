---
name: sketch
description: Build a design sketch as one HTML board, the page on the right and the open decisions on the left, so the user can switch options and see each one take effect. Use when a design choice (a screen, a section, an interaction, a layout) goes to the user as options, or when the user asks for a sketch or a mockup.
---

# Sketch

A sketch is one HTML file built from `board.html` in this folder.
The right side shows the whole page or section under discussion.
The left side lists each open decision as a code and its option letters.
Clicking a letter changes the page at once, and the parts it changed get an outline and a code tag such as `O3-B` for 1.5 seconds.

## Build one

1. Copy `board.html` to a new folder for the sketch, named for the decision, such as `~/sketches/credits-notice/index.html`.
   Never write a sketch into `/tmp` or a repo root.
2. Replace the JSON in `<script id="sketch-config">`:
   - `title`: the page title.
   - `viewport`: `null` to fill the right side, or `{"width":390,"height":844}` for a fixed screen such as a phone.
   - `decisions`: one entry per decision, in the order the user should take them.
     Each has `id` (`O1`, `O2`, ...), `q` (the question in a few words), `rec` (the recommended option letter) and `options`.
     Each option has `k` (`A`, `B`, ...), `label` (two to four words) and `pc` (one pro and one con).
     Keep codes stable for the whole conversation; a new decision gets the next free number.
3. Replace the contents of `<template id="sketch-page">` with the page: its own `<style>` and its markup.
   It renders in an iframe, so its CSS never touches the board.
   Build the whole page or section, not a fragment, so each option is seen in place.
4. Wire each option into the page:
   - `data-when="O3=A"` shows an element only for that option.
     `O3=A,B` matches either; `O3=A O4=B` needs both.
   - The iframe's `<html>` carries `data-o3="A"` for every decision, so CSS can change a style per option: `[data-o4=B] .notice{background:#fbeedd}`.
   - `data-touch="O4"` marks an element a CSS rule changes, so it gets the tag when `O4` switches.
     Elements with `data-when` are tagged without it.
5. Serve the folder and share it on the tailnet:
   ```
   python -m http.server <port> --bind 127.0.0.1 --directory <folder>
   tailscale serve --bg --https=<tailnet port> http://localhost:<port>
   ```
   Pick ports `tailscale serve status` does not already list.
   Get the host with `tailscale status --json | jq -r .Self.DNSName`.
   Send `https://<host>:<tailnet port>/`, never a localhost or file URL.
6. Screenshot it headless and look before you send it:
   ```
   chromium --headless=new --disable-gpu --hide-scrollbars --window-size=1400,900 --virtual-time-budget=2000 --screenshot=<png> http://localhost:<port>/
   ```
   On Windows use `msedge` with the same flags.
   A red "Sketch error" in the top bar means a `data-when` or `data-touch` names a decision or option that does not exist.
   Render the recommended option of every decision at least once.

## Taking picks back

The user presses Copy picks and pastes a line such as `Locked: O3-B. Leaning: O4-A.`
For each locked decision, add `"locked":"B"` to its entry in the config.
A decision with `locked` in the file stays locked in every browser and drops out of the left menu.
Leaning picks are not decisions; ask about them or keep them open.

When the user changes an option rather than picking one, edit that option or add a new letter, and keep the other codes.
When a new question comes up, add it as a new decision on the same board rather than starting a new file.

## The board stays minimal

The left menu shows only the code, the question and the letters.
Labels, pros and cons live in the hover tooltip and in the top bar.
Do not add text, headers or help to the menu; the user chose it this bare.

## In a repo with its own capture recipe

When a repo has a way to capture its real CSS and DOM, such as MyApp's control-app "Sketch from the live app", use that capture as the page inside `sketch-page` and edit only the parts the decisions change.
