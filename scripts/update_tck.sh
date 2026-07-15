#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/vendor/dmn-tck"
TCK_REPO_URL="https://github.com/dmn-tck/tck.git"
PIN_FILE="$VENDOR_DIR/PINNED_COMMIT"

if [[ $# -lt 1 ]]; then
  echo "Usage: scripts/update_tck.sh <commit-sha>"
  exit 1
fi

PINNED_COMMIT="$1"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

git clone "$TCK_REPO_URL" "$TMP_DIR/tck"
git -C "$TMP_DIR/tck" checkout "$PINNED_COMMIT"

rm -rf "$VENDOR_DIR"
mkdir -p "$VENDOR_DIR"

tar -C "$TMP_DIR/tck" --exclude=.git -cf - . | tar -C "$VENDOR_DIR" -xf -

echo "$PINNED_COMMIT" > "$PIN_FILE"
echo "$TCK_REPO_URL" > "$VENDOR_DIR/UPSTREAM_REPO"
echo "Updated vendored TCK snapshot at commit $PINNED_COMMIT"
