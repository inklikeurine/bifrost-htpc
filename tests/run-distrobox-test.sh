#!/usr/bin/bash
# Run setup.sh in a throwaway Kinoite distrobox, twice, and check the result.
#
# Usage: tests/run-distrobox-test.sh [IMAGE]
#   IMAGE defaults to the newest localhost/bifrost-test-kinoite image
#   (build one with tests/build-test-image.sh).
#
# The box gets its own home directory, so nothing touches your real ~/.config.
# Skipped in a container: rpm-ostree layering, the hostname, and starting sshd (the
# box shares the host's network, where port 22 is usually taken).
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
image=${1:-$(podman images --format '{{.Repository}}:{{.Tag}}' localhost/bifrost-test-kinoite | sort -V | tail -n1)}
[[ -n $image ]] || { echo "No test image; run tests/build-test-image.sh first." >&2; exit 1; }
box=bifrost-test
test_home=${XDG_CACHE_HOME:-$HOME/.cache}/bifrost-test/home
logs=$(dirname "$test_home")

echo "==> Creating $box from $image (home: $test_home)"
distrobox rm -f "$box" >/dev/null 2>&1 || true
# An interrupted earlier run can leave a container distrobox won't remove.
podman rm -f "$box" >/dev/null 2>&1 || true
rm -rf "$test_home"
mkdir -p "$test_home"
# An explicit pids limit: podman 4.9 turns distrobox's --pids-limit=-1 into a limit of 1.
distrobox create --yes --name "$box" --image "$image" --home "$test_home" --init \
    --additional-flags "--pids-limit=16384" >/dev/null
in_box() { distrobox enter "$box" -- "$@"; }
# distrobox mounts the host's / at /run/host.
setup=/run/host$repo/setup.sh

# The ISO installer adds Fedora Flatpaks that a container doesn't have. Install one
# from Flathub under the same app ID as a stand-in, to check setup.sh removes it.
echo "==> Installing org.kde.kmines as a stand-in for the installer's Flatpaks"
in_box sudo flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
in_box sudo flatpak install --system --noninteractive -y flathub org.kde.kmines >/dev/null 2>&1

echo "==> First run"
in_box sudo "$setup" >"$logs/run1.log" 2>&1 || { tail -20 "$logs/run1.log"; exit 1; }
echo "==> Second run (should change nothing), with the log seeded with 10 old runs"
in_box sudo bash -c 'for i in $(seq 10); do printf "===== old run %s: exit 0\n" "$i"; done >>/var/log/bifrost-setup.log'
in_box sudo "$setup" >"$logs/run2.log" 2>&1 || { tail -20 "$logs/run2.log"; exit 1; }

fail=0
check() {
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then echo "  ok    $what"; else echo "  FAIL  $what"; fail=1; fi
}

echo "==> Checks"
check "second run changed nothing" bash -c "! grep -qE '^ +(updated|enabled|added)|Installing' '$logs/run2.log'"
check "second run had no warnings" bash -c "! grep -q WARNING '$logs/run2.log'"
for app in rocks.shy.VacuumTube com.moonlight_stream.Moonlight com.valvesoftware.SteamLink org.moonfin.linux; do
    check "flatpak $app installed" in_box flatpak info --system "$app"
done
check "Fedora Flatpak stand-in removed" bash -c "! distrobox enter $box -- flatpak info --system org.kde.kmines"
check "autologin into Bigscreen" in_box grep -qx 'Session=plasma-bigscreen-wayland.desktop' /etc/plasmalogin.conf.d/50-bifrost-autologin.conf
check "rpm-ostree stages updates" in_box grep -qx 'AutomaticUpdatePolicy=stage' /etc/rpm-ostreed.conf
for timer in bifrost-flatpak-update bifrost-update-moonfin bifrost-update-dropout bifrost-weekly-reboot rpm-ostreed-automatic; do
    check "$timer.timer enabled" in_box systemctl is-enabled "$timer.timer"
done
check "sshd password login off" in_box bash -c "sudo sshd -T | grep -qx 'passwordauthentication no'"
check "policies.json force-installs the extension" in_box jq -e \
    '.policies.ExtensionSettings["leanback-for-dropout@inklikeurine.dev"].installation_mode == "force_installed"' \
    /etc/firefox/policies/policies.json
check "screen lock off" grep -qx 'Autolock=false' "$test_home/.config/kscreenlockerrc"
check "hidden apps include Bigscreen's defaults" grep -q '^blacklist=.*plasma-bigscreen-swap-session' "$test_home/.config/applications-blacklistrc"
check "hidden apps include every ID in config/hidden-apps.txt" bash -c "
    list=\$(sed -n 's/^blacklist=//p' '$test_home/.config/applications-blacklistrc' | tr , '\\n')
    sed -e 's/#.*//' -e '/^[[:space:]]*\$/d' '$repo/config/hidden-apps.txt' | while read -r id; do
        grep -qxF \"\$id\" <<<\"\$list\" || exit 1
    done"
check "Welcome Center pop-up off" grep -qx 'ShowUpdatePage=false' "$test_home/.config/plasma-welcomerc"
check "Baloo indexing off" grep -qx 'Indexing-Enabled=false' "$test_home/.config/baloofilerc"
check "Discover notifier off" grep -qx 'Hidden=true' "$test_home/.config/autostart/org.kde.discover.notifier.desktop"
check "SSH summary with host key fingerprints" grep -q 'SHA256:' "$logs/run1.log"
check "setup log ends with this run's exit code" in_box bash -c \
    "grep '^===== ' /var/log/bifrost-setup.log | tail -n1 | grep -q 'setup.sh: exit 0$'"
check "setup log trimmed to 8 runs" in_box bash -c "[[ \$(grep -c '^===== ' /var/log/bifrost-setup.log) == 8 ]]"
check "--room with a space is refused" bash -c "! distrobox enter $box -- sudo $setup --room 'Bad Name'"
check "bifrost-status runs" in_box /usr/local/bin/bifrost-status
check "policies.json force-installs uBlock Origin" in_box jq -e \
    '.policies.ExtensionSettings["uBlock0@raymondhill.net"].installation_mode == "force_installed"' \
    /etc/firefox/policies/policies.json
check "KWin rule forces Moonfin full screen" bash -c "
    f='$test_home/.config/kwinrulesrc'
    grep -qx 'rules=bifrost-moonfin' \"\$f\" && grep -qx 'count=1' \"\$f\" &&
        sed -n '/^\[bifrost-moonfin\]/,/^\[/p' \"\$f\" | grep -qx 'fullscreenrule=2'"
check "Bigscreen favorites written" grep -q '^storageId=bifrost-twitch.desktop$' "$test_home/.config/bigscreen-favs"
check "web-app icons installed" in_box test -f /usr/local/share/icons/hicolor/scalable/apps/bifrost-twitch.svg \
    -a -f /usr/local/share/icons/hicolor/512x512/apps/bifrost-dropout.png
check "update services run under systemd" in_box bash -c \
    'for s in bifrost-update-dropout bifrost-update-moonfin; do sudo systemctl start $s.service || exit 1; done'

check "Moonfin reinstall verifies its checksum" in_box bash -c \
    'sudo rm -f /var/lib/bifrost/moonfin-release && sudo /usr/local/bin/bifrost-update-moonfin'
fake_reboot='BIFROST_REBOOT_CMD="echo REBOOT" BIFROST_REBOOT_INTERVAL=2 BIFROST_REBOOT_MAX_WAIT=4 /usr/local/bin/bifrost-reboot'
check "weekly reboot goes ahead when nothing plays" in_box bash -c \
    "out=\$(sudo env $fake_reboot) && ! grep -q playing <<<\"\$out\" && grep -q REBOOT <<<\"\$out\""
check "weekly reboot waits while something plays" in_box bash -c \
    "sudo systemd-inhibit --what=idle --who=test --why=playback sleep 20 & sleep 1
     out=\$(sudo env $fake_reboot); kill %1 2>/dev/null
     grep -q 'Something is playing' <<<\"\$out\" && grep -q REBOOT <<<\"\$out\""

echo "==> Launching the Dropout web app headless (45 s)"
in_box bash -c 'MOZ_HEADLESS=1 timeout 45 /usr/local/bin/bifrost-webapp dropout https://watch.dropout.tv' >/dev/null 2>&1 || true
check "Leanback for Dropout installed and active in the web-app profile" jq -e \
    '[.addons[] | select(.id == "leanback-for-dropout@inklikeurine.dev" and .active)] | length == 1' \
    "$test_home/.local/share/bifrost/firefox/dropout/extensions.json"
check "uBlock Origin installed and active in the web-app profile" jq -e \
    '[.addons[] | select(.id == "uBlock0@raymondhill.net" and .active)] | length == 1' \
    "$test_home/.local/share/bifrost/firefox/dropout/extensions.json"

echo
if ((fail)); then
    echo "Some checks failed. Logs: $logs/run1.log, $logs/run2.log"
    exit 1
fi
echo "All checks passed. Remove the box with: distrobox rm -f $box"
