# HTPC Build — Kinoite + Plasma Bigscreen

One setup that installs and behaves the same on any HTPC, whatever its hardware.

## Goals

- **Apps:** YouTube, Jellyfin, Moonlight, Twitch (web app), Dropout (web app). No Netflix or other commercial streaming services.
- **Set-and-forget:** dead simple, as close to set-and-forget as possible.
- **Same everywhere:** every box behaves the same and is rebuilt from the same files in git.
- **Easy upkeep:** simple to maintain and update.
- **No Bigscreen customization:** use Bigscreen as shipped wherever possible.
- **Remote access:** SSH.
- **TVs on LAN only:** the TVs reach the local network but not the internet. The box supplies every app.

## Machines

### Bedroom HTPC

| | |
|---|---|
| Model | Lenovo ThinkCentre M910q Tiny (`10MUS33K00`) |
| CPU | Intel Core i5-7500T |
| RAM | 8 GB (7.6 GiB usable) |
| Storage | 238.5 GB NVMe |
| GPU | Intel HD Graphics 630: hardware decode for H.264, HEVC 10-bit, VP9 10-bit.|
| Network | Wi-Fi only. No Ethernet connected. |
| Remote | WeChip W1 air mouse (USB dongle). |
| TV | Roku TV, LAN only |

Before the reinstall, copy off anything worth keeping. At minimum, the 12 custom wallpapers in `~/.local/share/wallpapers/`: add them to this repo's `wallpapers/` folder.

### Living Room HTPC

| | |
|---|---|
| Model | Dell OptiPlex 3080 Micro (`D14U002`) |
| CPU / RAM | **Unknown.** Ships with anything from a Celeron to an i5. Check with F2 at boot → System Information. |
| GPU | Intel UHD 630 on i3/i5 models; weaker UHD 610 on Celeron/Pentium. |
| Video out | Rear HDMI 1.4: 4K at up to 30 Hz. |
| Network | M.2 2230 Wi-Fi slot, **no card installed**. Intel AX200 or AX210 is the safe Linux pick. Open the case first: if no white and black antenna cables reach the slot, you also need a 3080/5080/7080 MFF antenna kit. |
| TV | LG, LAN only |

## Platform

**Fedora Kinoite (the image-based version of Fedora KDE) + Plasma Bigscreen.**

- **Safe automatic updates:** Kinoite installs updates as a whole new system image in the background and switches to it on the next reboot. If an update breaks something, you pick the previous version from the boot menu. A bad update can't leave the box half-updated.
- **Layered packages:** Bigscreen isn't a Flatpak, so it's added to Kinoite as a "layered" package with one command. If Fedora's repos are briefly out of step, a layered package can hold up an update. The box keeps running the current version until it clears; it doesn't break. Keep the list of layered packages as short as possible.

## Setup method

**A git repo with one setup script, run on a fresh Kinoite install.**

- **Making changes:** edit the repo, then re-run the script on each box. Re-running is harmless.
  - Later, once the repo is stable: maybe have each box pull the repo and re-run the script weekly.
- **Maintenance:** Fedora builds and ships the OS. You only touch the repo when you change apps or settings.
- **Nothing machine-specific in the repo.** The hostname and Wi-Fi come from script options (`--room`, `--wifi`),
  so every box runs the same files. Screen resolution and IP are set by hand if needed.

### Setting up a box

1. Install Kinoite from the ISO. Create your account as an administrator.
2. Get the repo onto the box:

   ```bash
   git clone https://github.com/inklikeurine/bifrost-htpc.git && cd bifrost-htpc
   ```

3. Run the script:

   ```bash
   sudo ./setup.sh --room bedroom --wifi
   ```

   Steps are numbered (`[3/9] System files`), and downloads show progress bars. The first run also downloads
   the newest Fedora image with Bigscreen layered on, which can take a while.

   `--room bedroom` sets the hostname to `bifrost-bedroom` (letters, digits and dashes only). `--wifi` asks
   for the network and password (leave it out on Ethernet or if already connected). The run ends by printing the SSH command
   (`ssh you@bifrost-bedroom.local`), the box's IPv4 addresses and its host key fingerprints; check the
   fingerprints when you first connect.
4. Reboot. The first run staged a new OS image with Bigscreen layered on; autologin into Bigscreen starts
   working after this reboot.
5. Run `sudo ./setup.sh` again. It should report nothing to change.
6. Work through the per-box checklist below.

`--user NAME` picks the autologin account if you aren't running the script with `sudo` from it. Without an
internet connection the script stops before changing anything. `/var/log/bifrost-setup.log` keeps the last 8
runs: each run's exit code plus any warnings and errors. Over SSH, `bifrost-status` shows the OS deployments and layered
packages, each timer's last result and next run, the Moonfin and extension versions, and the installed apps.

### Updating a box

The repo is already cloned on the box, so pull the changes into it rather than cloning again
(`git clone` refuses a folder that isn't empty). Over SSH:

```bash
cd ~/bifrost-htpc
git pull
sudo ./setup.sh
```

You don't need `--room` or `--wifi` again: without `--room` the hostname stays as it is, and the Wi-Fi
connection is saved. If the run ends by asking for a reboot, reboot.

### What the script does

| Step | Details |
|---|---|
| Layered packages | `rpm-ostree upgrade --install=…` for each package in `config/layered-packages.txt` not already requested. `upgrade --install` layers onto the newest Fedora image: Bigscreen 6.7.5 (Fedora updates) needs a newer Plasma than the 44.1.7 ISO's 6.6.4, so layering onto the ISO's image would fail or pick an old Bigscreen snapshot. |
| Flatpaks | Adds Flathub, installs `config/flatpaks.txt` system-wide, and removes the installer's Fedora Flatpaks listed in `config/flatpaks-remove.txt`. |
| System files | Copies `files/usr/local/…` (helper scripts, Twitch and Dropout launchers and their icons, Firefox prefs and policy template) `files/etc/systemd/system/…` (timers) and `files/etc/wireplumber/…` (sound to the TV, see Sound). Writes the autologin file for your account. |
| Updates | Sets `AutomaticUpdatePolicy=stage` in `/etc/rpm-ostreed.conf` and turns on the timers below. |
| SSH | Adds `config/authorized_keys` to your `~/.ssh/authorized_keys` and turns on `sshd`. Password login goes off only once a key is in place (relabelled for SELinux) and `sshd -t` accepts the new config. Kinoite's firewall already allows SSH, and avahi makes `<hostname>.local` work on the LAN. |
| Firefox | Writes `/etc/firefox/policies/policies.json`, which force-installs Leanback for Dropout and uBlock Origin (against Twitch ads; addons.mozilla.org keeps it updated). |
| Moonfin | Installs the latest release's `.flatpak` bundle. |
| Per account | Copies `wallpapers/`. Turns off screen locking, auto-suspend on AC, Baloo file indexing, Discover's notifier and the Welcome Center pop-up. Adds a KWin window rule that forces Moonfin full screen (it has no setting for this and reopens however it was last closed). Hides `config/hidden-apps.txt` from Bigscreen and writes the favorites in the order of `config/favorites.txt`; re-running resets both to those lists. Until Moonfin's first start, sets aside the wallet KWallet made at the first password login (see the checklist). |

### Timers

Runs missed while the box was off happen at the next boot, except the reboot.

| Timer | When | What |
|---|---|---|
| `rpm-ostreed-automatic.timer` | daily (first 1 h after boot) | Downloads and stages OS updates. |
| `bifrost-flatpak-update.timer` | daily, ~03:00 | `flatpak update`, then removes unused runtimes. |
| `bifrost-update-moonfin.timer` | Sunday, ~03:30 | Installs a newer Moonfin release if there is one. |
| `bifrost-update-dropout.timer` | Sunday, ~03:30 | Points `policies.json` at the newest Leanback for Dropout release. |
| `bifrost-weekly-reboot.timer` | Sunday, 04:30 | Reboots, which applies the staged OS update. If something is playing (audio running, or an app keeping the screen awake), it rechecks every 30 min and reboots anyway after 3 h. |

### Troubleshooting

- **Roll back a bad update:** `sudo rpm-ostree rollback`, then reboot. Or pick the previous entry in the boot
  menu: hold Shift while the box starts. After a failed boot, Fedora shows the menu by itself.
- **See what happened:** `bifrost-status` for the summary, `journalctl -u 'bifrost-*'` for the timers,
  `/var/log/bifrost-setup.log` for setup runs.
- **Run an update now:** `sudo systemctl start bifrost-update-moonfin` (or `bifrost-update-dropout`,
  `bifrost-flatpak-update`).
- **Show a hidden app:** delete its line in `config/hidden-apps.txt` and re-run the script.

### Hidden apps

A fresh install shows about 30 desktop apps in Bigscreen. The script removes 8 of the installer's Fedora
Flatpaks and hides the rest except System Settings, Konsole and Discover (Okular and Gwenview stay installed,
hidden). Hiding writes `~/.config/applications-blacklistrc`, which Bigscreen reads to filter its app list. It
overrides the copy Bigscreen rewrites in `~/.config/plasma-bigscreen/` at each login, so the script repeats
Bigscreen's own default entries. Hidden apps stay installed. To show one again, delete its line and re-run.

### Repo layout

- `setup.sh`: the setup script.
- `config/`: the lists to edit: `flatpaks.txt`, `flatpaks-remove.txt`, `layered-packages.txt`, `favorites.txt`,
  `hidden-apps.txt`, `authorized_keys`.
- `files/`: files copied onto the box at the same path.
- `wallpapers/`: copied to `~/.local/share/wallpapers/` for every account.
- `tests/`: the container test (see Testing).

## Login

- **Autologin straight into the Bigscreen session.** Kinoite uses Plasma Login Manager, not SDDM. The script writes `/etc/plasmalogin.conf.d/50-bifrost-autologin.conf` with `User=`, `Session=plasma-bigscreen-wayland.desktop` (from the `plasma-bigscreen-wayland` package) and `Relogin=true`, which logs straight back in if the session exits or crashes.

## Sound

The TV gets the sound over HDMI, or over DisplayPort with an adapter cable. On Intel graphics both carry
audio. The HDMI/DisplayPort outputs share one sound card with the analog outputs, and PipeWire's session
manager (WirePlumber) ranks analog higher, so a box with a built-in speaker, like the ThinkCentre, plays
through that. `/etc/wireplumber/wireplumber.conf.d/50-bifrost-tv-audio.conf` puts the TV first.

The TV's output only counts as present while the screen is on: when Plasma turns the screen off after
10 minutes idle, sound falls back to the box's own speaker, and returns to the TV when the screen wakes.
Check with `wpctl status` (the TV's sink is `…hdmi-stereo`) or `cat /proc/asound/card0/eld*` (the TV's
name, with `eld_valid 1`).

## App plan

| Service | Client | Notes |
|---|---|---|
| YouTube | VacuumTube (Flatpak) | TV-style YouTube interface, works with arrow-key navigation |
| Jellyfin | Moonfin (Flatpak bundle, see below) | Turn on Moonfin's TV mode on each box |
| Moonlight | Moonlight (Flatpak `com.moonlight_stream.Moonlight`) | Preferred game streaming app |
| Steam Link | Steam Link (Flatpak `com.valvesoftware.SteamLink`) | Backup to Moonlight |
| Twitch | twitch.tv in Firefox, full screen, with uBlock Origin | Maybe develop a simple Leanback UI later |
| Dropout | dropout.tv in Firefox, full screen, with your extension | The extension supplies the 10-foot UI |

**The "web apps":** each is a launcher that opens Firefox in kiosk mode (full screen, no toolbars) with its own profile: `bifrost-webapp twitch https://www.twitch.tv` runs `firefox --kiosk --no-remote --class bifrost-twitch --profile ~/.local/share/bifrost/firefox/twitch https://www.twitch.tv`. The profile is created on first launch, and `firefox-user.js` is copied into it on every launch: no first-run pages, no restore-session prompt after the weekly reboot, autoplay on, notification prompts off. Both show up as normal tiles in Bigscreen with their own icons, and `--class` makes the open window use the launcher's icon too. The icons are in `files/usr/local/share/icons/hicolor/`: Dropout's comes from dropout.tv's web-app manifest, and Twitch's is the [Simple Icons](https://simpleicons.org) glitch logo on a purple circle. Kinoite's Firefox plays H.264, VP9 and AV1 out of the box, so Twitch needs no extra codec packages.

### Moonfin: Flatpak bundle

**Decided:** install the `.flatpak` file from Moonfin's GitHub releases (`Moonfin_Linux_v<version>.flatpak`, app ID `org.moonfin.linux`). It isn't on Flathub. No layering and no extra system packages.

**It can't update itself, so the script has to.**

- **Why:** Moonfin's build script makes the bundle without an update source, so Flatpak's normal updates (Discover, auto-updates) never see new Moonfin versions. The app shows a banner when a new version is out, but the only format Moonfin documents as updating in place is the AppImage.
- **What still updates normally:** Moonfin's runtime (GNOME Platform) comes from Flathub, which the script adds, so it updates with everything else.
- **The fix:** `bifrost-update-moonfin` (run by the script, then every Sunday) asks GitHub for the latest release. If it differs from the release it last installed, it downloads that `.flatpak`, checks it against the checksum GitHub publishes, and reinstalls over the old one, retrying once on failure. App data in `~/.var/app`, including settings and the server login, isn't touched.

### Dropout.tv

- **Extension:** https://github.com/inklikeurine/firefox-leanback-for-dropout
- **How to sign:** sign it on addons.mozilla.org as "self-distributed" (unlisted, so it isn't public). This can run automatically in GitHub Actions on each release with `web-ext sign --channel unlisted`.
- **How it updates:** `releases/latest/download/leanback-for-dropout.xpi` always points to the newest signed release. `bifrost-update-dropout` follows that link to the release's own versioned URL and writes that into `policies.json`. The URL changes with each release, so Firefox installs the new version on its next start.
- **Where the policy file goes:** `/etc/firefox/policies/policies.json`, read by Kinoite's preinstalled Firefox (tested: the extension installs signed and active). The Flathub Firefox uses a different path.

## Per-box checklist

Done once on each box, outside the repo.

- **Hostname and network:** run the script with `--room <room>` (giving `bifrost-<room>`) and, on Wi-Fi, `--wifi`.
  Use Ethernet if a cable can reach (better for Moonlight). All boxes join the same Wi-Fi network.
- **BIOS power setting:** set AC Recovery (or similar) to Power On, so the box comes back by itself after an outage.
- **Moonfin:** sign in and turn on TV mode. Moonfin stores the login in KWallet, which the script can't set up:
  when KWallet asks to create a wallet, choose the classic (Blowfish) type and leave the password blank, so
  autologin never meets a password prompt.
  - The first login after the install, with a password, has KWallet's PAM module create the wallet with that
    password. The script sets that wallet aside (to `~/.local/share/kwalletd/backup-<date>/`) if Moonfin
    hasn't started yet, so Moonfin's first start asks to create a new one.
  - If Moonfin instead asks for a wallet **password** on every start, the old wallet is still there: move
    `~/.local/share/kwalletd/kdewallet.*` into a backup folder, run `pkill ksecretd`, start Moonfin, create
    the wallet as above and sign in again.
- **TV:** LAN access only. Block its internet access at the router.

## House rules

- **Known password, stored in your password manager.** Keep a Fedora live USB nearby as a rescue disk.
- **No global key remapping:** a remap changes the key for every app, so fixing one app can break another.
- **Wallpapers:** add them to `wallpapers/` and re-run the script. Bigscreen's picker also always lists the stock
  wallpapers; it can't be pointed elsewhere, and Kinoite's system folders are read-only.

## Things to verify

These need real hardware; the container test can't cover them.

- **Notifications:** Bigscreen doesn't provide a notification service, so any app that shows a notification waits about 25 s for an answer that never comes. The script turns off Discover's notifier, the main source. If others turn out to be noticeable, the fix is a user-level dunst setup, which means one more layered package.
- **Closing the web apps with the remote:** kiosk mode has no close button. Try the remote's back and home keys, and Alt+F4 from a keyboard.
- **First boot into Bigscreen:** autologin, the favorites row and the wallpapers picker.
- **KWallet:** the wallet dialog matches the checklist, and a blank password really means no prompt after a reboot.
- **Sound on the TV** after a reboot and after the screen wakes (see Sound).
- **Hardware video decode** in Firefox and Moonlight (Intel VA-API; `libva-intel-media-driver` ships with Kinoite).
- **The weekly reboot** comes back into Bigscreen on its own, with the staged update applied.
- **Hidden apps and Welcome Center:** the home screen shows only the favorites plus System Settings, Konsole and Discover, and Welcome Center doesn't appear.
- **`--wifi`** connects, and the connection comes back after a reboot.
- **uBlock Origin** doesn't break Twitch playback.

## Testing

`tests/lint.sh` checks every script with shellcheck, the JSON files with `jq` and the launchers with
`desktop-file-validate`, in about a second. GitHub Actions runs it on every push and pull request.

`tests/` also runs `setup.sh` in a throwaway Kinoite container built from the ISO:

```bash
tests/build-test-image.sh ../Fedora-Kinoite-ostree-x86_64-44-1.7.iso
```

```bash
tests/run-distrobox-test.sh
```

The first command turns the ISO's OS tree into a podman image. The second creates a distrobox with its own home directory (your real `~/.config` is never touched), runs the script twice, checks the second run changes nothing, then checks the results, including launching the Dropout web app in headless Firefox and confirming both extensions install.

A container can't test rpm-ostree layering, the hostname, `--wifi`, starting `sshd` (the box shares the host's network), or anything that needs a screen. Last run with Kinoite 44.1.7 on 2026-10-19: all 37 checks passed.

## Sources

- Getting Plasma Bigscreen (Fedora package): https://plasma-bigscreen.org/get/
- Plasma Bigscreen source (favorites, app blacklist, session): https://invent.kde.org/plasma/plasma-bigscreen
- Kinoite unattended updates: https://fedoraproject.org/wiki/Changes/KDEKinoiteAutoUpdateByDefault
- Plasma Login Manager in Kinoite: https://fedoraproject.org/wiki/Changes/PlasmaLoginManager
- Plasma Login Manager settings page and `[Autologin]` section: https://discuss.cachyos.org/t/no-system-settings-module-kcm-for-plasma-login-manager/23463
- Atomic desktops drop FUSE 2 (AppImages): https://fedoraproject.org/wiki/Changes/AtomicDesktopDropFuse2
- Moonfin install options: https://github.com/Moonfin-Client/Moonfin-Core/wiki/Installation
- Moonfin releases: https://github.com/Moonfin-Client/Moonfin-Core/releases
- Moonfin bundle built without an update source: https://github.com/Moonfin-Client/Moonfin-Core/blob/main/build-linux.sh
- Moonfin update banner: https://github.com/Moonfin-Client/Moonfin-Core/releases/tag/2.4.0
- Firefox preinstalled on Kinoite: https://fedoramagazine.org/how-i-customize-fedora-silverblue-and-fedora-kinoite/
- Firefox policies.json location: https://firefox-admin-docs.mozilla.org/guides/policies-configuration/
- Firefox add-on signing for enterprise installs: https://www.extensionworkshop.com/documentation/enterprise/enterprise-distribution
- Self-distributed add-ons and update_url: https://extensionworkshop.com/documentation/publish/self-distribution/
- VacuumTube: https://flathub.org/en/apps/rocks.shy.VacuumTube
- Dell OptiPlex 3080 Micro setup and specifications: https://static.bhphoto.com/lit_files/676698.pdf
- Dell community, 3080 Micro 4K only over DisplayPort: https://www.dell.com/community/en/conversations/optiplex-desktops/new-4k-monitor-only-4k-on-dp-not-hdmi/662d7069904e1b4e08bc3b91
- Dell service manual, WLAN card: https://www.dell.com/support/manuals/en-us/optiplex-3080-micro/optiplex3080_micro_sm/installing-the-wlan-card?guid=guid-6c04c358-c1f3-4d95-8a03-8bd9b3ee59df&lang=en-us
- Intel media capabilities: https://www.intel.com/content/www/us/en/docs/onevpl/developer-reference-media-intel-hardware/1-1/overview.html
