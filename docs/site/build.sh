#!/usr/bin/env bash
# Build docs/gitbook into a static HonKit site.
#   docs/site/build.sh [output-dir]      (default: build/site)
# Run `npm ci` in docs/site first.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
OUT="${1:-$ROOT/build/site}"
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Copy the book. GitBook keeps figures in .gitbook/assets; static hosts and HonKit
# both skip dot-folders, so publish them as assets/ and rewrite the references.
cp -R "$ROOT/docs/gitbook/." "$WORK/"
mv "$WORK/.gitbook/assets" "$WORK/assets"
rm -rf "$WORK/.gitbook"
find "$WORK" -name '*.md' -print0 | xargs -0 sed -i.bak 's#\.gitbook/assets/#assets/#g'
find "$WORK" -name '*.md.bak' -delete

cp "$HERE/book.json" "$WORK/book.json"
ln -s "$HERE/node_modules" "$WORK/node_modules"

rm -rf "$OUT"
"$HERE/node_modules/.bin/honkit" build "$WORK" "$OUT" --log=warn
# Serve files as-is on GitHub Pages (no Jekyll processing).
touch "$OUT/.nojekyll"
echo "Site written to $OUT"
