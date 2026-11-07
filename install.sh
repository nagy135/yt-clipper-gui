#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
./scripts/build-app.sh
install_dir="${1:-/Applications}"
mkdir -p "$install_dir"
destination="$install_dir/YouTube Clipper.app"
if pgrep -f '/YouTube Clipper.app/Contents/MacOS/YTClipperGUI' >/dev/null; then
    printf 'Quit YouTube Clipper before installing an update.\n' >&2
    exit 1
fi
# ditto preserves the bundle and signature; no sudo is needed for a writable destination.
ditto 'dist/YouTube Clipper.app' "$destination"
touch "$destination"
printf '\nInstalled %s\nOpen it from Applications or run: open "%s"\n' "$destination" "$destination"
