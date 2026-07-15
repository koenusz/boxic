# Vendored DMN TCK

This directory is a vendored snapshot of the upstream DMN TCK corpus and local
fixtures used by Arbiter.

Vendoring policy:

- do not use submodules;
- keep `PINNED_COMMIT` updated to the exact upstream commit used for sync;
- keep this directory as plain files (no nested `.git`).

Use `scripts/update_tck.sh <commit-sha>` to refresh the snapshot.
