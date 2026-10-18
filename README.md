# HTPC Build — Kinoite + Plasma Bigscreen

One setup that installs and behaves the same on any HTPC, whatever its hardware.

## Goals

- **Apps:** YouTube, Twitch, Moonlight, Jellyfin, dropout.tv (web app), Twitch.tv (web app). No Netflix or other commercial streaming services.
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

Before the reinstall, copy off anything worth keeping. At minimum, the 12 custom wallpapers in `~/.local/share/wallpapers/`.

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

- **What the repo holds:** the setup script, the Flatpak list, Firefox `policies.json`, launchers for Twitch and Dropout, a `wallpapers/` folder, the autologin setting, and user config (screen-lock off, Bigscreen favorites, any notification fix that turns out to be needed).
- **New box:** install Kinoite, clone the repo, run the script, reboot.
- **Making changes:** running the script again is harmless. Changing a setting means editing the repo and re-running the script on each box.
  - After repo is stable, possibly have the box do a weekly check for updates to script, automated run.
- **Maintenance:** Fedora builds and ships the OS. You only touch the repo when you change apps or settings.
- **Hardware-specific settings stay out of the repo.** Screen resolution, hostname and Wi-Fi are set on each box, so the repo itself never differs between machines.
  - The hostname can be set by the script with `--room` (see below). Wi-Fi and IP stay manual for now; they may suit machine-specific dotfiles better.

### Setting up a box

1. Install Kinoite from the ISO. Create your account as an administrator.
2. Get the repo onto the box. It's private, so `git clone` needs credentials (for example a read-only deploy key); copying it over with `scp` also works.
3. Run the script, naming the room for the hostname:

   ```bash
   sudo ./setup.sh --room bedroom
   ```

4. Reboot. The first run stages a new OS image with Bigscreen layered on, and autologin into Bigscreen starts working after this reboot.
5. Run `sudo ./setup.sh` once more. It should report nothing to change.
6. Work through the per-box checklist below.

`--user NAME` picks the autologin account if you aren't running the script with `sudo` from it.

### What the script does

| Step | Details |
|---|---|
| Layered packages | `rpm-ostree upgrade --install=…` for each package in `config/layered-packages.txt`, unless already requested. `upgrade --install` layers onto the newest Fedora image: Bigscreen in Fedora's updates repo (6.7.5) needs a newer Plasma than the 44.1.7 ISO ships (6.6.4), so layering onto the ISO's image would fail or pick an old Bigscreen snapshot. |
| Flatpaks | Adds Flathub and installs `config/flatpaks.txt` system-wide. |
| System files | Copies `files/usr/local/…` (helper scripts, Twitch and Dropout launchers, Firefox prefs) and `files/etc/systemd/system/…` (timers). Writes the autologin file for your account. |
| Updates | Sets `AutomaticUpdatePolicy=stage` in `/etc/rpm-ostreed.conf` and turns on the timers below. Discover's own unattended updates also stay on. |
| SSH | Adds `config/authorized_keys` to your `~/.ssh/authorized_keys` and turns on `sshd`. Password login goes off only once a key is in place. |
| Firefox | Writes `/etc/firefox/policies/policies.json`, which force-installs Leanback for Dropout. |
| Moonfin | Installs the latest release's `.flatpak` bundle. |
| Per account | Copies `wallpapers/`, turns screen locking and auto-suspend on AC off, and writes the Bigscreen favorites (`~/.config/bigscreen-favs`) in the order of `config/favorites.txt`. Re-running the script resets the favorites to that list. |

### Timers

| Timer | When | What |
|---|---|---|
| `rpm-ostreed-automatic.timer` | daily | Downloads and stages OS updates. |
| `bifrost-flatpak-update.timer` | daily, 03:00 | `flatpak update`, then removes unused runtimes. |
| `bifrost-update-moonfin.timer` | Sunday, 03:30 | Installs a newer Moonfin release if there is one. |
| `bifrost-update-dropout.timer` | Sunday, 03:30 | Points `policies.json` at the newest Leanback for Dropout release. |
| `bifrost-weekly-reboot.timer` | Sunday, 04:30 | Reboots, which applies the staged OS update. |

### Repo layout

- `setup.sh`: the setup script.
- `config/`: the lists to edit: `flatpaks.txt`, `layered-packages.txt`, `favorites.txt`, `authorized_keys`.
- `files/`: files copied onto the box at the same path.
- `wallpapers/`: copied to `~/.local/share/wallpapers/` for every account.
- `tests/`: the container test (see Testing).

## Login

- **Autologin straight into the Bigscreen session.** Kinoite uses Plasma Login Manager, not SDDM. Autologin is set on its System Settings page ("Login Screen") or in the `[Autologin]` section (`User=`, `Session=`) of a file in `/etc/plasmalogin.conf.d/`. The script writes that file. The session is `plasma-bigscreen-wayland.desktop` (from the `plasma-bigscreen-wayland` package). `Relogin=true` logs straight back in if the session exits or crashes.

## App plan

| Service | Client | Notes |
|---|---|---|
| YouTube | VacuumTube (Flatpak) | TV-style YouTube interface, works with arrow-key navigation |
| Jellyfin | Moonfin (Flatpak bundle, see below) | Turn on Moonfin's TV mode on each box |
| Moonlight | Moonlight (Flatpak `com.moonlight_stream.Moonlight`) | Preferred game streaming app |
| Steam Link | Steam Link (Flatpak `com.valvesoftware.SteamLink`) | Backup to Moonlight |
| Twitch | twitch.tv in Firefox, full screen | potentially develop a simple Leanback UI. |
| Dropout | dropout.tv in Firefox, full screen, with your extension | The extension supplies the 10-foot UI. |

**The "web apps":** each one is a launcher file that opens Firefox in kiosk mode (full screen, no toolbars) with its own profile: `bifrost-webapp twitch https://www.twitch.tv` runs `firefox --kiosk --no-remote --profile ~/.local/share/bifrost/firefox/twitch https://www.twitch.tv`. The profile is created on first launch, and `files/usr/local/share/bifrost/firefox-user.js` is copied into it on every launch (no first-run pages, no restore-session prompt after the weekly reboot, autoplay allowed). Both launchers show up as normal tiles in Bigscreen. Kinoite's Firefox plays H.264, VP9 and AV1 out of the box, so Twitch needs no extra codec packages. **Test how to close them with the remote,** since kiosk mode has no close button.

### Moonfin: Flatpak bundle

**Decided:** install the `.flatpak` file from Moonfin's GitHub releases (`Moonfin_Linux_v<version>.flatpak`, app ID `org.moonfin.linux`). It isn't on Flathub. No layering and no extra system packages.

**It can't update itself, so the script has to.**

- **Why:** Moonfin's build script makes the bundle without an update source, so Flatpak's normal updates (Discover, auto-updates) never see new Moonfin versions. The app shows a banner when a new version is out, but the only format Moonfin documents as updating in place is the AppImage.
- **What still updates normally:** the Flatpak runtime Moonfin runs on comes from Flathub, so it updates with everything else. Flathub has to be set up on the box for the first install to work.
- **The fix:** every Sunday, a timer runs a small update script. It asks GitHub for Moonfin's latest release, compares it with the installed version, and if it's newer, downloads that release's `.flatpak` and installs it over the old one. Settings and the server login are kept.

### Dropout.tv

- **Custom Plugin:** The dropout.tv leanback extension for firefox is located at https://github.com/inklikeurine/firefox-leanback-for-dropout
- **How to sign:** sign it on addons.mozilla.org as "self-distributed" (unlisted, so it isn't public). This can run automatically in GitHub Actions on each release with `web-ext sign --channel unlisted`.
- **How it updates:** `releases/latest/download/leanback-for-dropout.xpi` always points to the newest signed release. `bifrost-update-dropout` follows that link to the release's own versioned URL and writes that into `policies.json`. The URL changes with each release, so Firefox installs the new version on its next start.
- **Where the policy file goes:** `/etc/firefox/policies/policies.json`. Tested: Kinoite's Firefox reads it, and the extension installs signed and active. This is for the Firefox that comes preinstalled on Kinoite (`/etc` is writable on Kinoite). If you switch to the Flathub Firefox, the path is different, so recheck it.

## Per-box checklist

These are the only things that differ between machines. They're done once on each box, outside the repo.

- **Hostname.**
  - bifrost-{roomName} e.g. bifrost-bedroom, bifrost-livingroom, etc.
- **Network:** Ethernet if a cable can reach (better for Moonlight). Otherwise Wi-Fi.
  - All PC's expected to connect to the same wi-fi network.
- **BIOS power setting:** set AC Recovery (or similar) to Power On, so the box comes back by itself after an outage.
- **Moonfin:** sign in and turn on TV mode. The first time Moonfin saves the login, KWallet asks to create a wallet: pick the classic (Blowfish) wallet and leave the password blank, so autologin never triggers a password prompt.
- **TV:** LAN access only. Block its internet access at the router.

## Same on every box (in the script)

- **Autologin** into the Bigscreen session (see Login).
- **Weekly reboot (e.g. 4 AM):** Kinoite applies staged updates at reboot, and an appliance that never reboots never gets them.
- **Flatpak auto-updates:** on, alongside the automatic system updates.
- **SSH with key login only:** turn off password login once your key works.
- **Known password, stored in your password manager:** keep a Fedora live USB nearby as a rescue disk.
- **Wallpapers:** the script copies the repo's `wallpapers/` folder into `~/.local/share/wallpapers/` for every account, and Bigscreen's wallpaper picker lists them. To add a wallpaper to every box, add it to the repo and re-run the script. The stock wallpapers stay in the picker too: it always includes the system wallpaper folder and can't be pointed somewhere else, and Kinoite's system folders are read-only.
- **Screen locking:** off.
- **No global key remapping:** a remap changes the key for every app, so fixing one app can break another.
- **KWallet:** Moonfin stores its server login in KWallet. Give the wallet a blank password so autologin doesn't trigger a password prompt when Moonfin opens. The script can't create the wallet, so this is a per-box step.
- **No auto-suspend on AC:** a sleeping box misses its update timers and may not wake for the remote.
- **Moonfin update check:** every Sunday.
- **Dropout extension update check:** every Sunday.

## Things to verify

These need real hardware; the container test can't cover them.

- **Notifications:** Bigscreen doesn't provide a notification service, so any app that shows a notification (Discover's update messages, for example) waits about 25 s for an answer that never comes. It may not be noticeable. If it is, the fix is a user-level dunst setup, which means one more layered package.
- **Closing the web apps with the remote:** kiosk mode has no close button. Try the remote's back and home keys, and Alt+F4 from a keyboard.
- **First boot into Bigscreen:** autologin, the favorites row and the wallpapers picker.
- **KWallet prompt:** that a blank-password wallet really means no prompt after a reboot.
- **Hardware video decode** in Firefox and Moonlight (Intel VA-API; `libva-intel-media-driver` ships with Kinoite).
- **The weekly reboot** comes back into Bigscreen on its own, with the staged update applied.

## Testing

`tests/` runs `setup.sh` in a throwaway Kinoite container built from the ISO:

```bash
tests/build-test-image.sh ../Fedora-Kinoite-ostree-x86_64-44-1.7.iso
```

```bash
tests/run-distrobox-test.sh
```

The first command turns the ISO's OS tree into a podman image. The second creates a distrobox with its own home directory (your real `~/.config` is never touched), runs the script twice, checks the second run changes nothing, and checks the results. That includes launching the Dropout web app in headless Firefox and confirming the extension installs.

A container can't test rpm-ostree layering, the hostname, starting `sshd` (the box shares the host's network), or anything that needs a screen. Last run with Kinoite 44.1.7 on 2026-10-18: all checks passed.

## Sources

- Getting Plasma Bigscreen (Fedora package): https://plasma-bigscreen.org/get/
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
