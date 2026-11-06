# First-party app slots — AEGIS Browser · OS Cloud · CoreX

The ISO reserves three `.deb` slots. Until the real package links are shared,
the image stays useful: **OS Cloud** and **CoreX** open their web apps
(`os-cloudflare.pages.dev`, `corex.site.je`) through stopgap desktop entries,
and the dock's **AEGIS Browser** tile targets the `aegis-browser` binary name.

## The three slots

| App | Source | Slot | Current stopgap |
| --- | --- | --- | --- |
| AEGIS Browser | github.com/abdul-mateen-14/AEGIS-BROWSER | `config/packages.chroot/*.deb` | dock tile runs `aegis-browser` (assumed binary name) |
| OS Cloud | os-cloudflare.pages.dev | same | `xdg-open https://os-cloudflare.pages.dev` |
| CoreX | corex.site.je | same | `xdg-open https://corex.site.je` |

## Wiring a .deb in (three ways, pick any)

1. **Repo variable (CI, no code changes)** — Settings → Secrets and variables
   → Actions → Variables → `AEGIS_APPS_DEB_URLS`, one URL per line. The ISO
   workflow downloads and stages them automatically.
2. **`debian-live/app-deb-urls.txt`** — commit the URLs (one per line,
   `#` comments). Works locally and in CI.
3. **Drop files** — put the `.deb`s directly in
   `debian-live/config/packages.chroot/` (gitignored) for local builds.

live-build installs everything in `packages.chroot/` via apt inside the
image, so archive dependencies resolve normally.

## When the links arrive — alignment checklist

- [ ] **Dock commands**: `shell/packaging/config.json` — replace the `cmd`
      values (`aegis-browser`, the two `xdg-open …` lines) with the real
      executables or desktop IDs from the packages.
- [ ] **Desktop entries**: delete the stopgap
      `theme/desktop-entries/aegis-web-oscloud.desktop` /
      `aegis-web-corex.desktop` if the debs ship their own entries (they will
      win — the entries are namespaced `aegis-web-*` and marked
      `X-Aegis-Slot`).
- [ ] **Binary names**: confirm the AEGIS Browser executable name
      (`aegis-browser` is an assumption) with
      `dpkg-deb -c aegis-browser_*.deb | grep bin/`.
- [ ] **Icons**: point the dock `icon` fields at the theme icon names the
      packages install (freedesktop icon lookup via `image://icons/`).
- [ ] Smoke-build once via **Actions → ISO → Run workflow**.
