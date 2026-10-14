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
- **Making changes:** write the script so running it again is harmless. Changing a setting then means editing the repo and re-running the script on each box.
  - After repo is stable, possibly have the box do a weekly check for updates to script, automated run.
- **Maintenance:** Fedora builds and ships the OS. You only touch the repo when you change apps or settings.
- **Hardware-specific settings stay out of the repo.** Screen resolution, hostname and Wi-Fi are set on each box, so the repo itself never differs between machines.
  - May want to set hostname / IP / wif-fi connection via this script, so box is already setup. This may be better suited to machine-specific dotfiles.

## Login

- **Autologin straight into the Bigscreen session.** Kinoite uses Plasma Login Manager, not SDDM. Autologin is set on its System Settings page ("Login Screen") or in the `[Autologin]` section (`User=`, `Session=`) of a file in `/etc/plasmalogin.conf.d/`. The script writes that file. Confirm the exact Bigscreen session name on the first install.

## App plan

| Service | Client | Notes |
|---|---|---|
| YouTube | VacuumTube (Flatpak) | TV-style YouTube interface, works with arrow-key navigation |
| Jellyfin | Moonfin (Flatpak bundle, see below) | Turn on Moonfin's TV mode on each box |
| Moonlight | Moonlight (Flatpak `com.moonlight_stream.Moonlight`) | Preferred game streaming app |
| Steam Link | Steam Link (Flatpak `com.valvesoftware.SteamLink`) | Backup to Moonlight |
| Twitch | twitch.tv in Firefox, full screen | potentially develop a simple Leanback UI. |
| Dropout | dropout.tv in Firefox, full screen, with your extension | The extension supplies the 10-foot UI. |

**The "web apps":** each one is a launcher file that opens Firefox in kiosk mode (full screen, no toolbars) with its own profile, for example `firefox --kiosk --no-remote -P twitch https://www.twitch.tv`. The setup script creates the profiles and launchers, and both show up as normal tiles in Bigscreen. **Test how to close them with the remote,** since kiosk mode has no close button.

### Moonfin: Flatpak bundle

**Decided:** install the `.flatpak` file from Moonfin's GitHub releases (`Moonfin_Linux_v<version>.flatpak`, app ID `org.moonfin.linux`). It isn't on Flathub. No layering and no extra system packages.

**It can't update itself, so the script has to.**

- **Why:** Moonfin's build script makes the bundle without an update source, so Flatpak's normal updates (Discover, auto-updates) never see new Moonfin versions. The app shows a banner when a new version is out, but the only format Moonfin documents as updating in place is the AppImage.
- **What still updates normally:** the Flatpak runtime Moonfin runs on comes from Flathub, so it updates with everything else. Flathub has to be set up on the box for the first install to work.
- **The fix:** every Sunday, a timer runs a small update script. It asks GitHub for Moonfin's latest release, compares it with the installed version, and if it's newer, downloads that release's `.flatpak` and installs it over the old one. Settings and the server login are kept.

## Dropout.tv

- **Custom Plugin:** The dropout.tv leanback extension for firefox is located at https://github.com/inklikeurine/firefox-leanback-for-dropout
- **How to sign:** sign it on addons.mozilla.org as "self-distributed" (unlisted, so it isn't public). This can run automatically in GitHub Actions on each release with `web-ext sign --channel unlisted`.
- **Where the policy file goes:** `/etc/firefox/policies/policies.json`. This is for the Firefox that comes preinstalled on Kinoite (`/etc` is writable on Kinoite). If you switch to the Flathub Firefox, the path is different, so recheck it.

## Per-box checklist

These are the only things that differ between machines. They're done once on each box, outside the repo.

- **Hostname.**
  - bifrost-{roomName} e.g. bifrost-bedroom, bifrost-livingroom, etc.
- **Network:** Ethernet if a cable can reach (better for Moonlight). Otherwise Wi-Fi.
  - All PC's expected to connect to the same wi-fi network.
- **BIOS power setting:** set AC Recovery (or similar) to Power On, so the box comes back by itself after an outage.
- **Moonfin:** sign in and turn on TV mode.
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
- **KWallet:** Moonfin stores its server login in KWallet. Give the wallet a blank password so autologin doesn't trigger a password prompt when Moonfin opens.
- **Moonfin update check:** every Sunday.
- **Dropout extension update check:** every Sunday.

## Things to verify

- **Notifications:** Bigscreen doesn't provide a notification service, so any app that shows a notification (Discover's update messages, for example) waits about 25 s for an answer that never comes. It may not be noticeable. If it is, the fix is a user-level dunst setup, which means one more layered package.

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
