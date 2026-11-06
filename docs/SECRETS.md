# Secrets & API Token Management

This document defines how credentials are handled in the Aegis OS repository.
**Rule zero: no credential ever enters the repository tree.**

## 1. What CI actually needs (nothing, by default)

Every workflow in this repo is designed to run with the **ephemeral
`GITHUB_TOKEN`** that GitHub provisions automatically for each run:

| Workflow | Auth used | Purpose |
|----------|-----------|---------|
| `iso.yml` | built-in `GITHUB_TOKEN` (implicit) | checkout, artifact upload |
| `shell-ci.yml` | built-in `GITHUB_TOKEN` (implicit) | checkout, artifact upload |
| `release.yml` | `${{ secrets.AEGIS_TOKEN || secrets.GITHUB_TOKEN }}` | publishing releases |

No manual secret setup is required to build ISOs or publish releases.

## 2. Optional repository secret: `AEGIS_TOKEN`

If you want release publishing to run under a personal access token (e.g. so
releases trigger other automations, or to lift the GITHUB_TOKEN rate limit):

1. GitHub → **Settings → Secrets and variables → Actions → New repository secret**
2. Name: `AEGIS_TOKEN`
3. Value: a fine-grained PAT for this repo with **Contents: Read & write**

`release.yml` picks it up automatically via
`${{ secrets.AEGIS_TOKEN || secrets.GITHUB_TOKEN }}` — the `||` fallback means
an empty/missing secret silently falls back to the built-in token.

### Register it from the CLI (one command)

```bash
AEGIS_TOKEN=ghp_xxx python3 scripts/set-actions-secret.py \
  --repo abdul-mateen-14/AEGIS-OS --name AEGIS_TOKEN
```

The script encrypts the value with the repository's libsodium public key
before upload; GitHub stores it encrypted and it can never be read back.

## 3. Optional repository variable: `AEGIS_APPS_DEB_URLS`

Not a secret — a plain **variable** (Settings → Secrets and variables →
Actions → Variables) listing newline- or space-separated URLs of
pre-built `.deb` packages to preinstall in the ISO. See
[`APP-SLOTS.md`](APP-SLOTS.md) for the slot contract and expected names.
If unset, the ISO builds without the three Aegis apps.

## 4. Local development store (never commit)

Maintainers keep their PAT outside the repo, e.g.:

```bash
mkdir -p ~/.secrets && printf '%s' 'ghp_xxx' > ~/.secrets/github.token
chmod 600 ~/.secrets/github.token
```

The repo `.gitignore` blocks `secrets/`, `*.token`, `*.pem`, `*.key` as a
safety net — a stray credential file cannot be committed by accident.

## 5. Token hygiene

- Prefer **fine-grained PATs** scoped to only this repository.
- Grant the minimum: `Contents: RW`, `Secrets: RW`, `Workflows: RW`.
- Rotate/revoke immediately if a token was pasted into chat, logs, or tickets.
- `GITHUB_TOKEN`-only CI means a leaked maintainer PAT can never touch builds.
