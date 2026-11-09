# AGENTS.md

Instructions for AI coding agents working on this repository. People: the
same rules apply to you.

## Read this first

**bifrost-htpc** sets up a home-theatre PC: a fresh Fedora Kinoite install
with Plasma Bigscreen, its apps, timers and settings, from one script
(`setup.sh`) and the files beside it. Every box runs the same files; the
script is safe to run again.

The maintainer does not read code. A change is judged by two things:

1. **The automated check** (lint), which runs on every pull request.
2. **Trying it** on a real box, using the steps you write in the pull
   request.

So your job is a change that passes lint, explained so that someone who
won't read the code can try it.

## What's where

| Path | What it is |
|---|---|
| `setup.sh` | The setup script. Run with `sudo` on the box; re-running is harmless |
| `config/` | The lists to edit: Flatpaks to install and remove, layered packages, Bigscreen favorites and hidden apps, SSH keys |
| `files/` | Files copied onto the box at the same path (helper scripts in `files/usr/local/bin/`, timers in `files/etc/systemd/system/`, launchers, Firefox settings, sound) |
| `wallpapers/` | Copied to every account's wallpaper folder |
| `tests/` | `lint.sh`, and the container test that needs a real machine (see Checking your work) |
| `README.md` | How a box is set up and maintained, and why: read it before changing behaviour |

**Nothing machine-specific goes in the repository.** The hostname and Wi-Fi
come from the script's options, so every box runs the same files.

## Checking your work

| Command | What it does | Where it runs |
|---|---|---|
| `tests/lint.sh` | **Validate and test**: shellcheck on every script, every JSON file through `jq`, every launcher through `desktop-file-validate`. About a second | On every pull request and push to `main`; run it yourself first |
| `tests/build-test-image.sh <Kinoite ISO>` then `tests/run-distrobox-test.sh` | Runs `setup.sh` twice in a throwaway Kinoite container built from the installer image, and checks the result | **Only the maintainer runs these**, on their own machine: they need podman, distrobox, the ISO and about 20 GB |

Some things only a real box shows (the README's "Things to verify" lists
them): Bigscreen after a reboot, sound on the TV, the remote, Wi-Fi,
hardware video decoding. **Only the maintainer tests on the real box.**

Run `tests/lint.sh` before you push and fix anything it finds. Never weaken
a check to get it to pass.

## Writing code

- **Bash, checked by shellcheck.** Scripts start with `#!/usr/bin/bash`.
- **Safe to run again.** A second run of `setup.sh` changes nothing; every
  step checks before it changes.
- **Keep Bigscreen as shipped** wherever possible, and keep the list of
  layered packages as short as possible (each one can hold up an update).
- **No global key remapping**: a remap changes the key for every app.
- **Explain changes to the box in the README** (what the script does, the
  timers, the checklist) in the same pull request.

## Your pull request

Fill in the pull request template:

- **One fix or feature per pull request.**
- **Say which AI tool wrote it**, and roughly how much of it.
- **Report three checks by these exact names**, and tick only what was
  actually done:
  - **Validated**: `tests/lint.sh` passed.
  - **Automated Test**: the container test (`tests/run-distrobox-test.sh`)
    passed. Only the maintainer can run it; leave it unticked otherwise and
    say so.
  - **Manual Review**: leave unticked. It means the maintainer tried the
    change on a real box.
- **Write "How to try it"** as numbered steps on the box, each something to
  do and what should happen, for example "Run `sudo ./setup.sh` twice. The
  second run reports nothing to change."

**Never say a change was "tested" or "works" unless a person tried it on a
real box.** Say exactly what you ran.

## Don't

- Don't commit personal data or anything machine-specific: passwords, Wi-Fi
  names, IP addresses, serial numbers, private keys.
- Don't add a license other than the Unlicense (`LICENSE`).
- Don't change `.github/`, `AGENTS.md` or `CLAUDE.md` without saying why in
  the pull request.
