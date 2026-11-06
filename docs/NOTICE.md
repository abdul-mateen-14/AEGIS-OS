# NOTICE — platform lineage, components and licenses

Aegis OS is an independent product built on top of proven open-source
components. This file records what we stand on and under which licenses —
kept out of the product front page by design, but never out of the credits.

## Platform lineage

- **Base core:** Ubuntu 26.04 LTS "resolute" — kernel, firmware, package
  universe. Kubuntu 26.04 ships KDE Plasma 6.6 LTS / Qt 6 natively, so no
  PPAs and no suite hacks are needed.
- **Compositor:** KWin 6 (KDE Plasma 6) — Wayland compositor, per the
  proposal's stack table.
- **ISO engineering:** live-build + live-boot/live-config.
- **Installer:** Calamares (fully graphical, offline-capable).
- **Boot splash:** Plymouth with the Aegis script theme.
- **Surface layers:** LayerShellQt.
- **Shell architecture:** follows the CutefishOS-proven pattern —
  "Cutefish started it, macOS polished it — Aegis OS finishes it."

## Component licenses (upstream)

| Component | License |
| --- | --- |
| Linux kernel | GPL-2.0 |
| KWin / KDE Plasma 6 | GPL-2.0+ / LGPL-2.1+ |
| Qt 6 | GPL-3.0 / LGPL-3.0 (open-source editions) |
| Calamares | GPL-3.0+ |
| live-build / live-boot / live-config | GPL-2.0+ |
| Plymouth | GPL-2.0+ |
| LayerShellQt | LGPL-3.0+ |
| SDDM | GPL-2.0+ |
| Dolphin / Konsole (KDE Apps) | GPL-2.0+ |
| NetworkManager | GPL-2.0+ / LGPL-2.1+ |

The above remain the property of their respective authors and are
redistributed under their own licenses. Aegis OS-specific work (the Aegis
Shell QML/C++, theme assets, packaging, CI pipelines, installer branding)
is licensed MIT — see [`LICENSE`](../LICENSE).

## Trademarks

Ubuntu and KDE are trademarks of their respective owners. Aegis OS is not
affiliated with, endorsed by, or sponsored by Canonical Ltd. or KDE e.V.

## Secure Boot status (M1)

The M1 ISO boots via a standalone GRUB EFI binary — every module and the
boot configuration are embedded, nothing is looked up externally. This is
the same best-effort pattern modern live-build uses when distro-signed
binaries are not wired up. Consequence: boot with **Secure Boot disabled**
(or via the firmware's one-time boot menu). Proper shim → signed-GRUB
chainloading is planned for M2.
