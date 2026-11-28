# AEGIS OS — the ISO layer

The distro vehicle, on the cutefish packaging model:

- `plymouth/aegis-logo/` — the boot splash. Derived from the cutefish-logo
  theme (GPL-2.0+, © Uri Herrera, Frédéric Gaudet, Charlie Brej lineage) —
  colors rebranded to the AEGIS abyss (#0B1020) and the logo swapped for
  the Aegis mark. The GPL header and author credits stay in the script.
- `packaging/` — one `debian/` directory per component
  (`iso/packaging/<component>/debian/`) + `build.sh`, the dependency-order
  build entry point cutefish uses.
- `live/` — the live-build config that assembles the ISO. Written when the
  Rust stack has its first installable set (round 3): kernel + firmware,
  the AEGIS compositor + shell, the branding payload, the installer.

## The Debian question

The desktop is Rust; the ISO still rides a Debian live system as the
hardware vehicle (kernel, firmware, NetworkManager — the invisible
plumbing every desktop distro needs). The user-facing stack — compositor,
shell, apps — is 100% Rust in `aegis-rs/`. Cutefish's own distro did the
same trick: a Qt/C++ desktop over an Ubuntu base.
