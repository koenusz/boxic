#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/vendor/dmn-tck"
PIN_FILE="$VENDOR_DIR/PINNED_COMMIT"
UPSTREAM_FILE="$VENDOR_DIR/UPSTREAM_REPO"
TREE_FILE="$VENDOR_DIR/UPSTREAM_TESTCASES_TREE"
MANIFEST_FILE="$VENDOR_DIR/VENDORED_FILES.sha256"

for required_file in \
  "$PIN_FILE" \
  "$UPSTREAM_FILE" \
  "$TREE_FILE" \
  "$MANIFEST_FILE"; do
  if [[ ! -s "$required_file" ]]; then
    echo "Missing or empty vendoring metadata: $required_file"
    exit 1
  fi
done

PINNED_COMMIT="$(tr -d '[:space:]' < "$PIN_FILE")"
UPSTREAM_URL="$(tr -d '[:space:]' < "$UPSTREAM_FILE")"
EXPECTED_TREE="$(tr -d '[:space:]' < "$TREE_FILE")"

if [[ ! "$PINNED_COMMIT" =~ ^[0-9a-fA-F]{40}$ ]]; then
  echo "PINNED_COMMIT must contain a full 40-character commit SHA"
  exit 1
fi

if [[ "$UPSTREAM_URL" != "https://github.com/dmn-tck/tck.git" ]]; then
  echo "Unexpected upstream repository: $UPSTREAM_URL"
  exit 1
fi

if [[ -d "$VENDOR_DIR/.git" ]]; then
  echo "Vendored directory must not contain nested .git metadata"
  exit 1
fi

(
  cd "$VENDOR_DIR"
  sha256sum --check --strict VENDORED_FILES.sha256 >/dev/null
)

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

git -C "$TMP_DIR" init --quiet
git -C "$TMP_DIR" remote add upstream "$UPSTREAM_URL"
git -C "$TMP_DIR" fetch --quiet --depth 1 upstream "$PINNED_COMMIT"

ACTUAL_COMMIT="$(git -C "$TMP_DIR" rev-parse FETCH_HEAD)"
ACTUAL_TREE="$(git -C "$TMP_DIR" rev-parse FETCH_HEAD:TestCases)"

if [[ "$ACTUAL_COMMIT" != "$PINNED_COMMIT" ]]; then
  echo "Fetched commit does not match pin: $ACTUAL_COMMIT"
  exit 1
fi

if [[ "$ACTUAL_TREE" != "$EXPECTED_TREE" ]]; then
  echo "Upstream TestCases tree does not match recorded tree: $ACTUAL_TREE"
  exit 1
fi

git -C "$TMP_DIR" checkout --quiet FETCH_HEAD -- TestCases

if ! diff -qr "$TMP_DIR/TestCases" "$VENDOR_DIR/TestCases" >/dev/null; then
  echo "Vendored TestCases differ from upstream commit $PINNED_COMMIT"
  exit 1
fi

echo "Vendored TCK corpus matches upstream commit: $PINNED_COMMIT"
