# CI on the GitHub free tier

The whole OS builds on **GitHub-hosted `ubuntu-latest` runners** with zero
self-hosting. For **public** repositories, standard runners are free with
**unlimited minutes**.

## Runner budget (per ISO build)

| Resource | Value | Notes |
| --- | --- | --- |
| vCPU / RAM | 4 / 16 GB | squashfs + dpkg are the hot stages |
| Disk | ~72 GB total, ~19 GB free | `scripts/ci/free-disk-space.sh` reclaims **~25–30 GB** (Android SDK, .NET, GHC, CodeQL, Boost, Miniconda, Swift, docker images) |
| Peak build usage | ~15 GB | minbase chroot (~1.5 GB) + packages + squashfs staging |
| Wall time | ~40–70 min | timeout capped at 150 min |

## Workflows

| Workflow | Trigger | Cost |
| --- | --- | --- |
| `iso.yml` | push to `main` touching `debian-live/` `shell/` `calamares/` `scripts/`, manual dispatch, or called by `release.yml` | 1 ISO build (~40–70 min) |
| `shell-ci.yml` | push/PR touching `shell/**` | ~5–8 min (compile + .deb) |
| `release.yml` | tag `v*.*.*` | 1 ISO build + Release publish |

`concurrency` groups cancel superseded runs on the same ref, so rapid pushes
never stack builds.

## Artifacts & releases

- Every ISO run uploads `aegis-os_<sha>.iso` + `.sha256` (14-day retention,
  `compression-level: 0` — the image is already compressed; upload is fast).
- Tag a release: `git tag v1.4.0-m1 && git push origin v1.4.0-m1` →
  `release.yml` builds once and publishes the ISO + checksum as a GitHub
  Release with generated notes.

## No secrets required

The pipeline needs **no repository secrets**: the build is fully
self-contained (no tokens, no signing keys). The only configurable input is
the repo **variable** `AEGIS_APPS_DEB_URLS` (a variable, not a secret — it's
just download URLs):

> Settings → Secrets and variables → Actions → **Variables** tab →
> `New repository variable` → Name: `AEGIS_APPS_DEB_URLS`,
> Value: one `.deb` URL per line.

## Keeping it free

1. Repo stays public (unlimited minutes; private would burn the 2,000
   min/month in ~40 builds).
2. Path filters keep `docs/**` edits from triggering 1-hour builds.
3. Concurrency cancellation avoids parallel 40-minute runs.
4. Retention is capped (14 days artifacts, 1 day for release candidates) —
   storage over quota is the only metered thing that can grow.
