# NOTICE — third-party components and licenses

This file records the provenance of everything in AEGIS OS that AEGIS did
not author. It is updated as the migration rounds land.

## Platform lineage (the new system, W102+)

| Component | Role | License | Provenance |
| --- | --- | --- | --- |
| Linux kernel | hardware vehicle | GPL-2.0 | upstream |
| Smithay | compositor framework | MIT | `aegis-compositor` adapted from Smithay's `minimal` example (MIT, © Smithay contributors) — notice retained in the source |
| wayland-rs (wayland-server/protocols) | Wayland protocol stack | MIT | crates.io |
| NetworkManager + firmware | invisible plumbing on the ISO | GPL-2.0+ / LGPL | upstream |
| plymouth (aegis-logo theme) | boot splash | GPL-2.0+ (theme) | derived from cutefish-logo (© 2016 Uri Herrera, 2013 Frédéric Gaudet, Charlie Brej lineage) — credits retained in the script, colors/logo rebranded |
| cutefish-compositor | window management, desktop shell, launchpad, lock screen | BSD-3 (© 2026 Reion Wong) | adopted AS-IS via submodule `desktop/compositor` (pinned upstream SHA) |
| cutefish-toolkit, -framework | base library, system API clients | BSD-3 (© 2026 Reion Wong) | adopted AS-IS via submodules `desktop/toolkit`, `desktop/framework` |
| fishui | the Qt widget library (the UI look) | BSD-3 (© 2026 Reion Wong) | adopted AS-IS via submodule `desktop/fishui` |
| cutefish-qt-plugins | Qt platform theme | BSD-3 (© 2026 Reion Wong) | adopted AS-IS via submodule `desktop/qt-plugins` |
| cutefish-core | system services (notifications, power …) | BSD-3 (© 2026 Reion Wong) | adopted AS-IS via submodule `desktop/core` |
| cutefish filemanager / settings / calculator | bases for Aegis Files / Settings / Calculator | BSD-3 (© 2026 Reion Wong) | adopted AS-IS via submodules `desktop/apps/*`, rebranded at package time |
| cutefish terminal | base for Aegis Terminal | MIT (© 2026 Reion Wong) | adopted AS-IS via submodule `desktop/apps/terminal` |
| cutefish icons | system icon fallback under the Aegis theme | GPL | adopted AS-IS via submodule `desktop/icons` |
| cutefishos | packaging MODEL + design reference | — | the per-component debian-dir layout and build.sh pattern |

## The old system (quarantined under old/)

| Component | License |
| --- | --- |
| KWin / KDE Plasma 6 | GPL-2.0+ / LGPL-2.1+ |
| Qt 6 | GPL-3.0 / LGPL-3.0 (open-source editions) |
| Calamares | GPL-3.0+ |
| live-build / live-boot | GPL-2.0+ |
| SDDM, Dolphin, Konsole | GPL-2.0+ / LGPL |

These remain the property of their respective authors and are
redistributed (while old/ survives) under their own licenses.

## License policy

Aegis OS-authored code (the whole `aegis-rs/` workspace, `iso/packaging/`
deb plumbing, `branding/` assets) is MIT — see [`LICENSE`](../LICENSE).
Third-party files carry their own licenses in place; nothing is
relicensed or stripped of its copyright notices.
