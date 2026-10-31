---
name: changelog
description: >
  Build a changelog page that shows one change at a time, grouped, in a few
  words, with a screenshot when the change is visual. Use when the user asks
  for a changelog, a release review, what would ship, or to show changes the
  way the Expo changelog does.
---

# Changelog

A changelog is one HTML page copied from `page.html` in this folder.
The left side lists the groups.
The right side shows one change: a short title, one sentence, when a person sees it, and Before and After screenshots when the change is something a person can see.

Use this when the user wants to review changes.
Use `sketch` when they are choosing a design.

## Build one

A changelog shows a change; it does not describe a change the reader cannot see.
Words alone are wrong for anything a person can see on screen.
If a screen is hard to reach, build the state that shows it.
Do not skip it.

1. Take the range the user named (commits, pull requests, or two branches).
   Read the diff and the commit messages for every change a person would notice.
   Put internal work that changes nothing they can see into a group called Internal, one line each, with no picture.
   Done when each noticed change is one item, no item mixes two changes, and every claim matches the diff.

2. Group the items by what the person would call them, in the order they should read.
   A group is a few words, such as Blog or Sign-up.
   Done when every item sits in one group.

3. Write each item.
   The title is the change in a few words.
   The body is one sentence.
   `when` says what a person does, or what state they are in, to see it, read from the code that opens it.
   Done when a person can understand the item and reach it without opening the diff.

4. Show each visual item the way a user sees it.
   Run the app on both sides of the range, such as one worktree on the base branch and one on the new branch.
   Drive each screen with the project's own driver or a headless browser, and save each probe so it can run again.
   - A changed screen gets a Before shot from the base branch and an After shot from the new branch.
   - A new screen gets the After shot, and a Before shot of what used to happen in its place, if anything did.
   - A screen with variants (offers, plans, empty and full) gets one shot of each variant.
   - Use real data: real prices, real copy, a signed-in account when the screen needs one.
     If a test stub shows "not available" or blank prices, give the stub real values and capture again.
   - Crop each shot to the change, so its text is readable at 720 pixels wide.
   - A wording change across many places gets a `words` table of real Before and After strings from the diff, not a screenshot.
   A change that is only speed or structure gets no picture.
   Done when every visual item has its shots or its words table, and you opened every shot and saw the change in it.

5. Copy `page.html` to `~/changelogs/<slug>/index.html`, unless the user named a folder.
   Never write it into `/tmp` or a repo root.
   Replace the JSON in `<script id="changelog-config">` with the groups and items.
   Each item takes `date`, `title`, `body`, and, when they apply, `when`, `shots`, and `words`:

   ```json
   {
     "title": "Out of credits page",
     "body": "Running short opens one page with a pack, Plus, and Studio.",
     "when": "A signed-in person presses Generate with fewer credits than the try costs.",
     "shots": [
       { "label": "Before: a small top-up box", "src": "shots/credits-before.png" },
       { "label": "After", "src": "shots/credits-after.png" }
     ],
     "words": [{ "before": "Rotate 90° CCW", "after": "Rotate 90° anticlockwise" }]
   }
   ```

   Put the screenshots in `shots/` next to the page.

6. Serve the folder so it outlives the session, and share it on the tailnet:

   ```
   systemd-run --user --unit=changelog-<slug> python -m http.server <port> --bind 127.0.0.1 --directory <folder>
   tailscale serve --bg --https=<tailnet port> http://localhost:<port>
   ```

   Off Linux, use the platform's own user service.
   Read `tailscale serve status` first, and do not reuse a port or path it lists.
   Get the host with `tailscale status --json`.
   Open the tailnet URL yourself before you send it.
   When you update a page that is already served, fetch its URL; restart the file server if it does not answer.

7. Look at every item before you send the link, not only the first.
   Open the page headless once for each item, with `show(<index>)` in place of `show(0)` in a copy you delete after.
   On Windows use `msedge` with `--headless=new --disable-gpu --hide-scrollbars --window-size=1400,2400 --screenshot=<png>`.
   Fetch the served URL and one shot through it.
   Done when every item shows its title, sentence, `when`, and readable shots, and the served URL returns the new page.
