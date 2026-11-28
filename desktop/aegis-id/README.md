# Aegis ID

The identity module (Aegis-original, MIT) — the user asked for an
*"Aegis ID in settings"*. It is the device's identity card: avatar with
the user's initial, device name, user, OS version, and the privacy line
(no telemetry, identity stays local) as a design contract rather than
decoration.

## Why a standalone app (and not a Settings sidebar page)

The Settings app is the adopted cutefish submodule — never fork-patched.
A sidebar page inside it would require patching upstream QML. So Aegis
ID ships as its own window in the same glass language (the Aegis design
tokens directly — `#0B1020` abyss, one floating card, hairline border,
the blue ramp `#5B8BFF → #1D4FEA`), registered in the default app set
([`../DEFAULT-APPS.md`](../DEFAULT-APPS.md)). When the packaging round
lands, the desktop entry places it in the Settings category; if a
deeper Settings integration turns out to be necessary, it will be done
as an upstream-style contribution or an install-time override — not a
source fork.

## The shared identity

The identity fields on this card are the SAME fields the browser's
primary sync backend owns: `email` and `username` come from the
`aegis-sync` database (reused read-only by the OS backend), and
`avatar_url` / `display_name` are OS-owned fields served by
`aegis-sync-os` — `GET /v1/os/identity` for this card, `PUT` to update
them, and public resolution by username so any surface renders the same
identity as the browser. One account, one password, same avatar and
name everywhere — see [`docs/SYNC-OS.md`](../../docs/SYNC-OS.md).
Wiring this card to the live backend (login + avatar editing) lands
with the Store/account round.

## Build

```bash
cmake -S desktop/aegis-id -B build/aegis-id -DCMAKE_BUILD_TYPE=Release
cmake --build build/aegis-id
./build/aegis-id/aegis-id
```

Deps: Qt 6 (Quick). The CMake install puts the binary in `/usr/bin` and
the desktop entry in `/usr/share/applications`; the icon comes from the
`aegis-icons` theme (`aegis-id`, the blue identity-card squircle).
