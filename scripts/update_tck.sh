#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/vendor/dmn-tck"
TCK_REPO_URL="https://github.com/dmn-tck/tck.git"

if [[ $# -ne 1 ]]; then
  echo "Usage: scripts/update_tck.sh <40-character-commit-sha>"
  exit 1
fi

PINNED_COMMIT="$1"

if [[ ! "$PINNED_COMMIT" =~ ^[0-9a-fA-F]{40}$ ]]; then
  echo "Pinned revision must be a full 40-character commit SHA"
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

git -C "$TMP_DIR" init --quiet tck
git -C "$TMP_DIR/tck" remote add upstream "$TCK_REPO_URL"
git -C "$TMP_DIR/tck" -c gc.auto=0 fetch --quiet --depth 1 upstream "$PINNED_COMMIT"
git -C "$TMP_DIR/tck" -c gc.auto=0 checkout FETCH_HEAD -- \
  TestCases .gitignore LICENSE-ASL-2.0.txt README.md

RESOLVED_COMMIT="$(git -C "$TMP_DIR/tck" rev-parse FETCH_HEAD)"
TESTCASES_TREE="$(git -C "$TMP_DIR/tck" rev-parse FETCH_HEAD:TestCases)"

if [[ "$RESOLVED_COMMIT" != "$PINNED_COMMIT" ]]; then
  echo "Fetched commit does not match requested pin: $RESOLVED_COMMIT"
  exit 1
fi

rm -rf "$VENDOR_DIR"
mkdir -p "$VENDOR_DIR"
cp -a "$TMP_DIR/tck/TestCases" "$VENDOR_DIR/TestCases"
cp "$TMP_DIR/tck/.gitignore" "$VENDOR_DIR/.gitignore"
cp "$TMP_DIR/tck/LICENSE-ASL-2.0.txt" "$VENDOR_DIR/LICENSE-ASL-2.0.txt"
cp "$TMP_DIR/tck/README.md" "$VENDOR_DIR/README.md"

printf '%s\n' "$PINNED_COMMIT" > "$VENDOR_DIR/PINNED_COMMIT"
printf '%s\n' "$TCK_REPO_URL" > "$VENDOR_DIR/UPSTREAM_REPO"
printf '%s\n' "$TESTCASES_TREE" > "$VENDOR_DIR/UPSTREAM_TESTCASES_TREE"

(
  cd "$VENDOR_DIR"
  find TestCases -type f -print0 | sort -z | xargs -0 sha256sum
) > "$VENDOR_DIR/VENDORED_FILES.sha256"

echo "Updated official DMN TCK TestCases at commit $PINNED_COMMIT"
