#!/usr/bin/bash
# Turn a Fedora Kinoite ISO into a podman image for testing setup.sh in distrobox.
#
# Usage: tests/build-test-image.sh Fedora-Kinoite-Installer-45-1.4.x86_64.iso
#        (or an older Fedora-Kinoite-ostree-x86_64-44-1.7.iso)
#
# Produces two images:
#   localhost/kinoite-iso:<version>         the OS tree from the ISO, as installed
#   localhost/bifrost-test-kinoite:<version> the same plus what distrobox needs to start
#
# Needs podman, 7z or xorriso, and for ISOs before Fedora 45 unsquashfs. Uses about 20 GB of scratch space,
# deleted at the end. Runs without root.
set -euo pipefail

iso=$(realpath "${1:?usage: $0 path/to/Fedora-Kinoite-*.iso}")
work=$(mktemp -d "${XDG_CACHE_HOME:-$HOME/.cache}/bifrost-image.XXXXXX")
# Files in the checkout belong to the user namespace's root after podman unshare.
trap 'podman unshare rm -rf "$work"' EXIT

echo "==> Extracting install.img from $(basename "$iso")"
if command -v 7z >/dev/null; then
    7z x -y -o"$work" "$iso" images/install.img >/dev/null
else
    xorriso -osirrox on -indev "$iso" -extract /images/install.img "$work/images/install.img" 2>/dev/null
fi

# The ref looks like fedora/44/x86_64/kinoite; its version like 44.1.7.
if [[ $(od -An -tx4 -j1024 -N4 "$work/images/install.img" | tr -d ' ') == e0f5e1e2 ]]; then
    # Fedora 45's install.img is EROFS (magic e0f5e1e2 at byte 1024), and its repo keeps
    # SELinux labels that rootless podman can't write. So mount it read-only with
    # erofsfuse (FUSE needs /dev/fuse and, inside the container only, SYS_ADMIN) and
    # check out straight from it.
    echo "==> Checking out the OS tree from the EROFS image"
    podman run --rm --device /dev/fuse --cap-add SYS_ADMIN -v "$work:/work:z" \
        registry.fedoraproject.org/fedora:latest bash -c '
        set -e
        dnf -y -q install erofs-fuse ostree >/dev/null 2>&1
        mkdir -p /mnt/img
        erofsfuse /work/images/install.img /mnt/img 2>/dev/null
        repo=/mnt/img/ostree/repo
        ref=$(cd "$repo/refs/heads" && find . -type f | sed "s|^\./||" | head -n1)
        echo "    ref: $ref"
        echo "$ref" >/work/ref
        ostree --repo="$repo" log "$ref" | sed -n "s/^Version: *//p" | head -n1 >/work/version
        ostree --repo="$repo" checkout --user-mode "$ref" /work/rootfs'
    ref=$(<"$work/ref")
    rm -f "$work/images/install.img"
else
    echo "==> Extracting the ostree repo"
    # Errors about owners and xattrs are expected without root; the checkout below
    # doesn't need them, and the test image restores them from the RPM database.
    unsquashfs -q -n -d "$work/squash" "$work/images/install.img" ostree >/dev/null 2>&1 || true
    rm -f "$work/images/install.img"
    ref=$(cd "$work/squash/ostree/repo/refs/heads" && find . -type f | sed 's|^\./||' | head -n1)
    echo "    ref: $ref"

    echo "==> Checking out $ref"
    podman run --rm -v "$work:/work:z" "registry.fedoraproject.org/fedora-toolbox:$(cut -d/ -f2 <<<"$ref")" bash -c "
        dnf -y -q install ostree >/dev/null 2>&1
        ostree --repo=/work/squash/ostree/repo log '$ref' | sed -n 's/^Version: *//p' | head -n1 >/work/version
        ostree --repo=/work/squash/ostree/repo checkout --user-mode '$ref' /work/rootfs"
    chmod -R u+w "$work/squash"
    rm -rf "$work/squash"
fi
version=$(<"$work/version")
# Use the matching Fedora release for helpers.
release=$(cut -d/ -f2 <<<"$ref")
toolbox=registry.fedoraproject.org/fedora-toolbox:$release

echo "==> Importing localhost/kinoite-iso:$version"
root=$work/rootfs
# ostree keeps /etc in /usr/etc and creates /var at boot; a container needs both in place.
mv "$root/usr/etc" "$root/etc"
mkdir -p "$root"/var/{home,mnt,opt,roothome,srv,tmp,log,cache,lib} "$root"/var/usrlocal/{bin,sbin,lib,share} "$root/run/media"
chmod 1777 "$root/var/tmp" "$root/tmp"
chmod 0700 "$root/var/roothome"
# The unprivileged checkout lost owners, setuid bits and file capabilities. Put them
# back from the RPM database before importing; doing it in an image layer would copy
# every file.
podman unshare chroot "$root" sh -c 'rpm --setugids -a; rpm --setperms -a; rpm --setcaps -a' >/dev/null 2>&1 || true
podman unshare test -u "$root/usr/bin/sudo" || { echo "Couldn't restore file permissions." >&2; exit 1; }
podman unshare bash -c "tar --numeric-owner -C '$root' -cf - . | podman import \
    --change 'CMD [\"/bin/bash\"]' --message 'Kinoite $version from $(basename "$iso")' \
    - localhost/kinoite-iso:$version" >/dev/null

echo "==> Building localhost/bifrost-test-kinoite:$version"
ctx=$work/ctx
mkdir -p "$ctx"
util_linux=$(podman run --rm "localhost/kinoite-iso:$version" rpm -q --qf '%{version}-%{release}' util-linux-core)
podman run --rm -v "$ctx:/out:z" "$toolbox" \
    bash -c "cd /out && dnf -q download --repo=fedora,updates pigz util-linux-script-$util_linux"
cat >"$ctx/Containerfile" <<EOF
FROM localhost/kinoite-iso:$version
# distrobox's init needs pigz and script, which Kinoite doesn't ship. Kinoite has no
# dnf, so mark distrobox's base setup as done rather than let it look for one.
# Fedora 45's rpm checks signatures against keys it has been given, so give it the
# release's key first (in /usr/share/pki from Fedora 45, /etc/pki before).
COPY *.rpm /tmp/rpms/
RUN for key in /usr/share/pki/rpm-gpg/RPM-GPG-KEY-fedora-$release-primary \\
        /etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-$release-primary; do \\
        if [ -e "\$key" ]; then rpmkeys --import "\$key"; fi; \\
    done && rpm -i /tmp/rpms/*.rpm && rm -rf /tmp/rpms && touch /.containersetupdone
EOF
podman build -q -t "localhost/bifrost-test-kinoite:$version" "$ctx" >/dev/null

echo "==> Done: localhost/bifrost-test-kinoite:$version"
