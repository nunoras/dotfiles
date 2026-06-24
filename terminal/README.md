# Windows Terminal

Only the **appearance** is synced — not the whole `settings.json`.

[`appearance.json`](appearance.json) holds the look (color scheme, opacity,
font, padding, cursor). `install.ps1` merges it into `profiles.defaults` of
whatever `settings.json` exists on the machine, leaving the machine's own
profile list (conda, VS, etc.) untouched.

Why merge instead of symlink the whole file:
- Windows Terminal **rewrites `settings.json` atomically**, which would break a
  symlink, and
- the profile list is **machine-specific**, so copying one machine's file would
  clobber another's profiles.

To change the look everywhere: edit `appearance.json`, commit, and run
`install.ps1` on each machine. Current scheme: **One Half Dark**, 90% acrylic.
