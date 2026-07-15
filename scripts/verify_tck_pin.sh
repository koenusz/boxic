#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/vendor/dmn-tck"
PIN_FILE="$VENDOR_DIR/PINNED_COMMIT"
UPSTREAM_URL="https://github.com/dmn-tck/tck.git"

if [[ ! -f "$PIN_FILE" ]]; then
  echo "Missing pin file: $PIN_FILE"
  exit 1
fi

PINNED_COMMIT="$(tr -d '[:space:]' < "$PIN_FILE")"

if [[ -z "$PINNED_COMMIT" ]]; then
  echo "PINNED_COMMIT is empty"
  exit 1
fi

if [[ -d "$VENDOR_DIR/.git" ]]; then
  echo "Vendored directory must not contain nested .git metadata"
  exit 1
fi

UPSTREAM_REFS="$(git ls-remote "$UPSTREAM_URL" | awk '{print $1}')"

if ! printf '%s\n' "$UPSTREAM_REFS" | grep -qx "$PINNED_COMMIT"; then
  echo "Pinned commit not found upstream: $PINNED_COMMIT"
  exit 1
fi

echo "Vendored TCK pin is valid: $PINNED_COMMIT"
