#!/usr/bin/bash
# bifrost-htpc setup.
#
# Run on a fresh Fedora Kinoite install, and again after any change to this repo.
# Running it again is harmless: each step checks before it changes anything.
#
# Usage: sudo ./setup.sh [--user NAME] [--room NAME] [--wifi]
#   --user NAME  account to log in automatically (default: the account that ran sudo)
#   --room NAME  set the hostname to bifrost-NAME, e.g. --room bedroom
#   --wifi       ask for a Wi-Fi network and its password, and connect to it
#
# /var/log/bifrost-setup.log keeps the last 8 runs: each run's exit code, warnings and errors.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
user=${SUDO_USER:-}
room=""
wifi=false
args=$*

usage() { sed -n '2,13s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"; }

while (($#)); do
    case $1 in
        --user) user=${2:?--user needs a name}; shift 2 ;;
        --room) room=${2:?--room needs a name}; shift 2 ;;
        --wifi) wifi=true; shift ;;
        -h | --help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done
room=${room,,}
if [[ -n $room && ! $room =~ ^[a-z0-9]([a-z0-9-]{0,53}[a-z0-9])?$ ]]; then
    echo "--room must be letters, digits and dashes, e.g. --room livingroom" >&2
    exit 2
fi

# Steps are numbered "[n/total]"; total is counted once the options are known.
step=0
total=0
log() { step=$((step + 1)); printf '\n==> [%d/%d] %s\n' "$step" "$total" "$*"; }
note() { printf '    %s\n' "$*"; }
# Warnings and errors also go to this run's entry in the setup log (see finish).
notes=""
record() { if [[ -n $notes ]]; then echo "$*" >>"$notes"; fi; }
warn() { printf '    WARNING: %s\n' "$*" >&2; record "WARNING: $*"; }
error() { printf 'ERROR: %s\n' "$*" >&2; record "ERROR: $*"; }

# Flatpak and curl only draw progress bars on a terminal; under systemd or with output
# redirected, they get quiet options instead.
flatpak_opts=(--system -y)
[[ -t 1 ]] || flatpak_opts+=(--noninteractive)

# Lines of a config list, without comments or blank lines.
read_list() { sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$1"; }

# put SRC DEST [MODE]: install SRC at DEST only if it differs. Returns 1 if unchanged.
put() {
    local src=$1 dest=$2 mode=${3:-0644}
    if [[ -f $dest ]] && cmp -s "$src" "$dest" && [[ $(stat -c %a "$dest") == "${mode#0}" ]]; then
        return 1
    fi
    install -D -m "$mode" "$src" "$dest"
    note "updated $dest"
}

if ((EUID != 0)); then
    echo "Run this with sudo: sudo $0 $args" >&2
    exit 1
fi
if [[ -z $user || $user == root ]] || ! id "$user" >/dev/null 2>&1; then
    echo "Can't tell which account to set up. Run it with sudo from that account, or pass --user NAME." >&2
    exit 1
fi
if ! grep -q '^VARIANT_ID=kinoite' /etc/os-release; then
    echo "This isn't Fedora Kinoite." >&2
    exit 1
fi

# The terminal gets the full output, untouched so progress bars still draw.
# /var/log/bifrost-setup.log gets each run's exit code, warnings and errors, and keeps
# the last 8 runs.
setup_log=/var/log/bifrost-setup.log
started=$(date '+%F %T')
tmp=$(mktemp)
notes=$(mktemp)

finish() {
    local code=$?
    {
        echo "===== $started: setup.sh${args:+ $args}: exit $code"
        cat "$notes"
    } >>"$setup_log"
    local runs
    runs=$(grep -c '^===== ' "$setup_log")
    if ((runs > 8)); then
        awk -v skip=$((runs - 8)) '/^===== /{n++} n>skip' "$setup_log" >"$tmp" && cat "$tmp" >"$setup_log"
    fi
    rm -f "$tmp" "$notes"
}
trap finish EXIT
# A command that stops the script (set -e) gets logged with its line number.
trap 'error "line $LINENO: \"$BASH_COMMAND\" failed (exit $?)"' ERR

mapfile -t accounts < <(getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 && $7 !~ /(nologin|false)$/ {print $1}')
# Wi-Fi and Hostname (optional), 7 system steps, one per account with a home, then
# Connect with SSH.
total=8
for account in "${accounts[@]}"; do
    [[ -d $(getent passwd "$account" | cut -d: -f6) ]] && total=$((total + 1))
done
$wifi && total=$((total + 1))
[[ -n $room ]] && total=$((total + 1))

# A booted Kinoite install has /run/ostree-booted. A test container doesn't, so
# rpm-ostree steps are skipped there.
booted=false
[[ -e /run/ostree-booted ]] && booted=true
# systemd is running (rather than, say, a container without an init).
systemd_up=false
[[ -d /run/systemd/system ]] && systemd_up=true
reboot_needed=false

# ---------------------------------------------------------------------------
if $wifi; then
    log "Wi-Fi"
    read -rp "    Wi-Fi network name: " ssid </dev/tty
    if nmcli -t -f NAME connection show | grep -qxF "$ssid"; then
        note "a connection named $ssid already exists"
    # --ask makes nmcli prompt for the password itself, so it never passes through this script.
    elif nmcli --ask device wifi connect "$ssid" </dev/tty; then
        note "connected to $ssid"
    else
        warn "couldn't connect to $ssid"
    fi
fi

# Everything below downloads something. Stop now, before changing anything, rather
# than partway through.
if ! curl -fsS -o /dev/null --max-time 15 --retry 2 https://dl.flathub.org/repo/flathub.flatpakrepo; then
    error "no internet connection. Connect the box (or run with --wifi) and try again."
    exit 1
fi

# ---------------------------------------------------------------------------
if [[ -n $room ]]; then
    log "Hostname"
    want="bifrost-$room"
    if [[ $(hostname) == "$want" ]]; then
        note "already $want"
    elif hostnamectl set-hostname "$want"; then
        note "set to $want"
    else
        warn "couldn't set the hostname to $want"
    fi
fi

# ---------------------------------------------------------------------------
log "Layered packages"
mapfile -t packages < <(read_list "$repo/config/layered-packages.txt")
if ! $booted; then
    note "not a booted Kinoite system (test container?); skipping rpm-ostree"
else
    # deployments[0] is the newest deployment: the pending one if an update is staged.
    mapfile -t requested < <(rpm-ostree status --json | jq -r '.deployments[0]["requested-packages"][]?')
    missing=()
    for pkg in "${packages[@]}"; do
        printf '%s\n' "${requested[@]}" | grep -qxF "$pkg" || missing+=("$pkg")
    done
    if ((${#missing[@]})); then
        note "adding ${missing[*]}"
        note "this downloads the newest Fedora image too (often 1-2 GB) and can take a while"
        # "upgrade --install" layers onto the newest Fedora image rather than the one
        # installed from the ISO. Bigscreen in Fedora's updates repo needs the Plasma
        # version of the newest image.
        rpm-ostree upgrade "${missing[@]/#/--install=}"
        reboot_needed=true
    else
        note "already requested: ${packages[*]}"
    fi
    if rpm-ostree status --json | jq -e '.deployments[0].booted | not' >/dev/null; then
        reboot_needed=true
    fi
fi

# ---------------------------------------------------------------------------
log "Flatpaks"
flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
mapfile -t apps < <(read_list "$repo/config/flatpaks.txt")
to_install=()
for app in "${apps[@]}"; do
    flatpak info --system "$app" >/dev/null 2>&1 || to_install+=("$app")
done
if ((${#to_install[@]})); then
    note "installing ${to_install[*]}"
    flatpak install "${flatpak_opts[@]}" flathub "${to_install[@]}"
else
    note "all installed"
fi
# Fedora Flatpaks the Kinoite installer adds that an HTPC doesn't need.
mapfile -t unwanted < <(read_list "$repo/config/flatpaks-remove.txt")
to_remove=()
for app in "${unwanted[@]}"; do
    flatpak info --system "$app" >/dev/null 2>&1 && to_remove+=("$app")
done
if ((${#to_remove[@]})); then
    note "removing ${to_remove[*]}"
    flatpak uninstall "${flatpak_opts[@]}" "${to_remove[@]}"
fi

# ---------------------------------------------------------------------------
log "System files"
# Helper scripts, launchers and shared data. /usr/local is writable on Kinoite.
while IFS= read -r -d '' src; do
    rel=${src#"$repo/files/"}
    mode=0644
    [[ -x $src ]] && mode=0755
    put "$src" "/$rel" "$mode" || true
done < <(find "$repo/files/usr" "$repo/files/etc/systemd" -type f -print0)

# Autologin straight into the Bigscreen session.
sed "s/@USER@/$user/g" "$repo/files/etc/plasmalogin.conf.d/50-bifrost-autologin.conf" >"$tmp"
put "$tmp" /etc/plasmalogin.conf.d/50-bifrost-autologin.conf || true
if $booted && [[ ! -e /usr/share/wayland-sessions/plasma-bigscreen-wayland.desktop ]] && ! $reboot_needed; then
    warn "the Bigscreen session file is missing, so autologin will fail"
fi

# ---------------------------------------------------------------------------
log "Automatic updates"
# Stage OS updates in the background; the weekly reboot applies them. Discover's
# background updater is turned off per account below, so these timers do all updating.
if grep -qx 'AutomaticUpdatePolicy=stage' /etc/rpm-ostreed.conf; then
    note "rpm-ostree already stages updates"
else
    if grep -q '^#\?AutomaticUpdatePolicy=' /etc/rpm-ostreed.conf; then
        sed -i 's/^#\?AutomaticUpdatePolicy=.*/AutomaticUpdatePolicy=stage/' /etc/rpm-ostreed.conf
    else
        sed -i '/^\[Daemon\]/a AutomaticUpdatePolicy=stage' /etc/rpm-ostreed.conf
    fi
    note "rpm-ostree now stages updates automatically"
    if $systemd_up; then systemctl try-reload-or-restart rpm-ostreed.service || true; fi
fi

timers=(
    rpm-ostreed-automatic.timer
    bifrost-flatpak-update.timer
    bifrost-update-moonfin.timer
    bifrost-update-dropout.timer
    bifrost-weekly-reboot.timer
)
$systemd_up && systemctl daemon-reload
for timer in "${timers[@]}"; do
    if systemctl is-enabled --quiet "$timer" 2>/dev/null; then
        continue
    fi
    if $systemd_up; then
        systemctl enable --now --quiet "$timer"
    else
        systemctl enable --quiet "$timer"
    fi
    note "enabled $timer"
done

# ---------------------------------------------------------------------------
log "SSH"
# A fresh install has no host keys until sshd first starts, and sshd -t below needs them.
if ! compgen -G '/etc/ssh/ssh_host_*_key.pub' >/dev/null; then
    ssh-keygen -A >/dev/null
    note "generated SSH host keys"
fi
home=$(getent passwd "$user" | cut -d: -f6)
keys="$repo/config/authorized_keys"
have_key=false
if [[ -s $keys ]] && grep -q '^\(ssh-\|ecdsa-\|sk-\)' "$keys"; then
    have_key=true
    install -d -m 0700 -o "$user" -g "$(id -gn "$user")" "$home/.ssh"
    touch "$home/.ssh/authorized_keys"
    # Add the repo's keys; keep any added on the box by hand.
    added=0
    while IFS= read -r key; do
        grep -qxF "$key" "$home/.ssh/authorized_keys" || { echo "$key" >>"$home/.ssh/authorized_keys"; added=$((added + 1)); }
    done < <(grep '^\(ssh-\|ecdsa-\|sk-\)' "$keys")
    chown "$user:$(id -gn "$user")" "$home/.ssh/authorized_keys"
    chmod 0600 "$home/.ssh/authorized_keys"
    # Files created by root can carry the wrong SELinux label, and sshd then ignores the
    # key. Password login goes off below, so that would lock SSH out.
    if command -v selinuxenabled >/dev/null && selinuxenabled; then
        restorecon -R "$home/.ssh"
    fi
    ((added)) && note "added $added key(s) to $home/.ssh/authorized_keys"
fi
if $have_key; then
    if put "$repo/files/etc/ssh/sshd_config.d/50-bifrost.conf" /etc/ssh/sshd_config.d/50-bifrost.conf; then
        # Never restart sshd on a config it rejects: that would take SSH down.
        if ! sshd -t; then
            rm -f /etc/ssh/sshd_config.d/50-bifrost.conf
            warn "sshd rejected 50-bifrost.conf; removed it, password login stays on"
        else
            note "password login is now off"
            if $systemd_up; then
                systemctl try-reload-or-restart sshd.service || warn "sshd didn't restart; check: systemctl status sshd"
            fi
        fi
    fi
else
    warn "no key in config/authorized_keys; leaving SSH password login on"
fi
if ! systemctl is-enabled --quiet sshd.service 2>/dev/null; then
    if $systemd_up; then
        systemctl enable --now --quiet sshd.service || warn "sshd didn't start; check: systemctl status sshd"
    else
        systemctl enable --quiet sshd.service
    fi
    note "enabled sshd"
fi

# ---------------------------------------------------------------------------
log "Firefox policy"
/usr/local/bin/bifrost-update-dropout || warn "couldn't check for a new extension release; will retry on Sunday"

log "Moonfin"
/usr/local/bin/bifrost-update-moonfin || warn "couldn't install Moonfin; will retry on Sunday"

# ---------------------------------------------------------------------------
# Per-user settings, for every human account.

# Bigscreen keeps its favorites in ~/.config/bigscreen-favs: one [Favs][N] group per
# app, with the fields its app list reports for that desktop file.
write_favorites() {
    local dest=$1
    python3 - "$repo/config/favorites.txt" "$dest" "$2" <<'PY'
import configparser, os, sys

favs_list, dest, home = sys.argv[1:4]
dirs = [
    f"{home}/.local/share/applications",
    "/usr/local/share/applications",
    "/var/lib/flatpak/exports/share/applications",
    "/usr/share/applications",
]

def kconfig_value(v):
    v = v.replace("\\", "\\\\").replace("\n", "\\n").replace("\t", "\\t")
    return "\\s" + v[1:] if v.startswith(" ") else v

ids = []
with open(favs_list) as f:
    for line in f:
        line = line.split("#", 1)[0].strip()
        if line:
            ids.append(line)

out = []
for storage_id in ids:
    path = next((os.path.join(d, storage_id) for d in dirs if os.path.isfile(os.path.join(d, storage_id))), None)
    if path is None:
        print(f"    skipping favorite {storage_id}: not installed", file=sys.stderr)
        continue
    entry = configparser.RawConfigParser(interpolation=None, strict=False)
    entry.optionxform = str
    entry.read(path, encoding="utf-8")
    de = entry["Desktop Entry"]
    fields = {
        "storageId": storage_id,
        "entryPath": de.get("Exec", ""),
        "desktopPath": path,
        "name": de.get("Name", storage_id),
        "comment": de.get("Comment", ""),
        "icon": de.get("Icon", ""),
        "categories": ",".join(c for c in de.get("Categories", "").split(";") if c),
        "startupNotify": "true" if de.get("StartupNotify", "").lower() == "true" else "false",
    }
    out.append(f"[Favs][{sum(1 for l in out if l.startswith('[Favs]'))}]")
    out.extend(f"{k}={kconfig_value(v)}" for k, v in fields.items())
    out.append("")

with open(dest, "w", encoding="utf-8") as f:
    f.write("\n".join(out))
PY
}

# Apps hidden from the Bigscreen home screen. Bigscreen reads [Applications] blacklist
# from applications-blacklistrc, and ~/.config/applications-blacklistrc overrides the copy
# its envmanager rewrites in ~/.config/plasma-bigscreen/ at every login. Our key replaces
# Bigscreen's, so its own defaults (envmanager/config.h, 6.7.5) are repeated here.
bigscreen_hidden=(
    waydroid.com.android.calculator2 waydroid.com.android.camera2 waydroid.com.android.contacts
    waydroid.com.android.deskclock waydroid.com.android.documentsui waydroid.com.android.gallery3d
    waydroid.com.android.inputmethod.latin waydroid.com.android.settings waydroid.org.lineageos.eleven
    waydroid.org.lineageos.etar waydroid.org.lineageos.jelly waydroid.org.lineageos.recorder
    org.kde.drkonqi.coredump.gui org.kde.kdeconnect.app org.kde.kdeconnect.sms plasma-bigscreen-swap-session
)
mapfile -t hidden < <(read_list "$repo/config/hidden-apps.txt")
hidden=("${bigscreen_hidden[@]}" "${hidden[@]}")
welcome_version=$(rpm -q --qf '%{version}' plasma-welcome 2>/dev/null || echo 1.0)

for account in "${accounts[@]}"; do
    acct_home=$(getent passwd "$account" | cut -d: -f6)
    [[ -d $acct_home ]] || continue
    log "Settings for $account"
    group=$(id -gn "$account")
    as_user() {
        runuser -u "$account" -- env HOME="$acct_home" XDG_CONFIG_HOME="$acct_home/.config" "$@"
    }

    # Wallpapers: Bigscreen's picker lists ~/.local/share/wallpapers alongside the stock ones.
    if find "$repo/wallpapers" -mindepth 1 -not -name .gitkeep -print -quit | grep -q .; then
        as_user mkdir -p "$acct_home/.local/share/wallpapers"
        while IFS= read -r -d '' src; do
            rel=${src#"$repo/wallpapers/"}
            dest="$acct_home/.local/share/wallpapers/$rel"
            if put "$src" "$dest"; then chown "$account:$group" "$dest"; fi
        done < <(find "$repo/wallpapers" -type f -not -name .gitkeep -print0)
        # put creates parent directories as root; hand them back.
        chown -R "$account:$group" "$acct_home/.local/share/wallpapers"
    fi

    # Screen locking off.
    as_user kwriteconfig6 --file kscreenlockerrc --group Daemon --key Autolock false
    as_user kwriteconfig6 --file kscreenlockerrc --group Daemon --key LockOnResume false
    # Never suspend on AC power: a sleeping box misses its update timers and may not wake
    # for the remote.
    as_user kwriteconfig6 --file powerdevilrc --group AC --group SuspendAndShutdown --key AutoSuspendAction 0
    note "screen lock and auto-suspend off"

    # Apps hidden from the home screen (config/hidden-apps.txt).
    {
        echo "[Applications]"
        echo "blacklist=$(IFS=,; echo "${hidden[*]}")"
    } >"$tmp"
    as_user mkdir -p "$acct_home/.config/autostart"
    if put "$tmp" "$acct_home/.config/applications-blacklistrc"; then
        chown "$account:$group" "$acct_home/.config/applications-blacklistrc"
    fi

    # Welcome Center opens on first login (LastSeenVersion empty) and after big Plasma
    # updates (ShowUpdatePage); stop both so it never lands on the TV.
    as_user kwriteconfig6 --file plasma-welcomerc --group General --key ShowUpdatePage false
    if [[ -z $(as_user kreadconfig6 --file plasma-welcomerc --group General --key LastSeenVersion) ]]; then
        as_user kwriteconfig6 --file plasma-welcomerc --group General --key LastSeenVersion "$welcome_version"
    fi
    # No file indexing: there are no documents to search, and it costs CPU and disk.
    as_user kwriteconfig6 --file baloofilerc --group "Basic Settings" --key Indexing-Enabled false
    # No Discover notifier: the timers handle updates, and its notifications stall for
    # ~25 s in Bigscreen, which has no notification service.
    printf '[Desktop Entry]\nHidden=true\n' >"$tmp"
    if put "$tmp" "$acct_home/.config/autostart/org.kde.discover.notifier.desktop"; then
        chown "$account:$group" "$acct_home/.config/autostart/org.kde.discover.notifier.desktop"
    fi
    note "Welcome Center, file indexing and Discover's notifier off"

    # Bigscreen favorites, in the order of config/favorites.txt.
    as_user mkdir -p "$acct_home/.config"
    write_favorites "$tmp" "$acct_home"
    if put "$tmp" "$acct_home/.config/bigscreen-favs"; then
        chown "$account:$group" "$acct_home/.config/bigscreen-favs"
    else
        note "Bigscreen favorites unchanged"
    fi
done

# ---------------------------------------------------------------------------
log "Connect with SSH"
note "ssh $user@$(hostname -s).local"
note "IPv4 addresses: $(hostname -I 2>/dev/null | tr ' ' '\n' | grep -v : | xargs)"
note "host key fingerprints (check these on your first connection):"
for key in /etc/ssh/ssh_host_*_key.pub; do
    note "  $(ssh-keygen -lf "$key")"
done

printf '\n==> Done\n'
if $reboot_needed; then
    note "Reboot to finish: the new OS image with the layered packages is staged."
    note "After the reboot, run this script once more to check everything."
fi
