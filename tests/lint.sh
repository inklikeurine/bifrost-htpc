#!/usr/bin/bash
# Quick checks for the repo: shellcheck on every script, JSON syntax, desktop files.
# Runs in seconds; CI runs it on every push (.github/workflows/lint.yml).
#
# Needs jq and desktop-file-validate. Uses shellcheck if installed, else its container.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail=0
step() { printf '==> %s\n' "$*"; }

step "shellcheck"
mapfile -t scripts < <(grep -rlE '^#!/usr/bin/(env )?bash' setup.sh files tests)
if command -v shellcheck >/dev/null; then
    shellcheck -S warning "${scripts[@]}" || fail=1
else
    podman run --rm -v "$PWD:/mnt:ro,z" -w /mnt docker.io/koalaman/shellcheck:stable -S warning "${scripts[@]}" || fail=1
fi

step "JSON"
while IFS= read -r -d '' f; do
    jq empty "$f" || { echo "invalid JSON: $f"; fail=1; }
done < <(find files config -name '*.json' -print0)

step "desktop files"
while IFS= read -r -d '' f; do
    desktop-file-validate "$f" || fail=1
done < <(find files -name '*.desktop' -print0)

if ((fail)); then
    echo "Lint failed."
    exit 1
fi
echo "Lint passed."
