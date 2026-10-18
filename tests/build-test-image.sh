#!/usr/bin/bash
# Turn a Fedora Kinoite ISO into a podman image for testing setup.sh in distrobox.
#
# Usage: tests/build-test-image.sh Fedora-Kinoite-ostree-x86_64-44-1.7.iso
#
# Produces two images:
#   localhost/kinoite-iso:<version>         the OS tree from the ISO, as installed
#   localhost/bifrost-test-kinoite:<version> the same plus what distrobox needs to start
#
# Needs podman, unsquashfs, and 7z or xorriso. Uses about 20 GB of scratch space,
# deleted at the end. Runs without root.
set -euo pipefail

iso=$(realpath "${1:?usage: $0 path/to/Fedora-Kinoite-ostree-*.iso}")
work=$(mktemp -d "${XDG_CACHE_HOME:-$HOME/.cache}/bifrost-image.XXXXXX")
# Files in the checkout belong to the user namespace's root after podman unshare.
trap 'podman unshare rm -rf "$work"' EXIT

echo "==> Extracting install.img from $(basename "$iso")"
if command -v 7z >/dev/null; then
    7z x -y -o"$work" "$iso" images/install.img >/dev/null
else
    xorriso -osirrox on -indev "$iso" -extract /images/install.img "$work/images/install.img" 2>/dev/null
fi

echo "==> Extracting the ostree repo"
# Errors about owners and xattrs are expected without root; the checkout below
# doesn't need them, and the test image restores them from the RPM database.
unsquashfs -q -n -d "$work/squash" "$work/images/install.img" ostree >/dev/null 2>&1 || true
rm -f "$work/images/install.img"
ref=$(cd "$work/squash/ostree/repo/refs/heads" && find . -type f | sed 's|^\./||' | head -n1)
echo "    ref: $ref"

echo "==> Checking out $ref"
podman run --rm -v "$work:/work:z" registry.fedoraproject.org/fedora-toolbox:44 bash -c "
    dnf -y -q install ostree >/dev/null 2>&1
    ostree --repo=/work/squash/ostree/repo log '$ref' | sed -n 's/^Version: *//p' | head -n1 >/work/version
    ostree --repo=/work/squash/ostree/repo checkout --user-mode '$ref' /work/rootfs"
version=$(<"$work/version")
chmod -R u+w "$work/squash"
rm -rf "$work/squash"

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
podman run --rm -v "$ctx:/out:z" registry.fedoraproject.org/fedora-toolbox:44 \
    bash -c "cd /out && dnf -q download --repo=fedora,updates pigz util-linux-script-$util_linux"
cat >"$ctx/Containerfile" <<EOF
FROM localhost/kinoite-iso:$version
# distrobox's init needs pigz and script, which Kinoite doesn't ship. Kinoite has no
# dnf, so mark distrobox's base setup as done rather than let it look for one.
COPY *.rpm /tmp/rpms/
RUN rpm -i /tmp/rpms/*.rpm && rm -rf /tmp/rpms && touch /.containersetupdone
EOF
podman build -q -t "localhost/bifrost-test-kinoite:$version" "$ctx" >/dev/null

echo "==> Done: localhost/bifrost-test-kinoite:$version"
