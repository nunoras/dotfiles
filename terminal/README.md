# Windows Terminal

Only the **appearance** is synced — not the whole `settings.json`.

[`appearance.json`](appearance.json) holds the look (color scheme, opacity,
font, padding, cursor). [`schemes.json`](schemes.json) holds any custom color
schemes that aren't built into Windows Terminal (e.g. Catppuccin Mocha).
`install.ps1` merges the appearance into `profiles.defaults` and the schemes
into `schemes` (by name) of whatever `settings.json` exists on the machine,
leaving the machine's own profile list (conda, VS, etc.) untouched.

Why merge instead of symlink the whole file:
- Windows Terminal **rewrites `settings.json` atomically**, which would break a
  symlink, and
- the profile list is **machine-specific**, so copying one machine's file would
  clobber another's profiles.

To change the look everywhere: edit `appearance.json` (and `schemes.json` if
adding a custom scheme), commit, and run `install.ps1` on each machine.
Current scheme: **Catppuccin Mocha**, 90% acrylic.
