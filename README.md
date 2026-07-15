# Arbiter

Arbiter is an Elixir umbrella project for FEEL and DMN engines with an internal
DMN TCK harness.

## Apps

- `arbiter_feel`: FEEL parsing and evaluation API.
- `arbiter_dmn`: DMN model loading and decision evaluation using FEEL.
- `arbiter_dmn_tck`: Internal TCK discovery, execution, and reporting.

## Current status

- umbrella scaffolding complete;
- complete official DMN TCK snapshot vendored under `vendor/dmn-tck` at the
  revision in `PINNED_COMMIT`;
- official namespaced test documents are discovered and normalized by the
  native Elixir loader;
- native Elixir TCK runner with explicit statuses;
- machine-readable CSV and JSON report generation.

Engine compatibility with the official corpus is still in progress. A loaded
test is not treated as passing unless it executes through Arbiter and its
result matches the upstream expected value.

## Commands

```bash
mix deps.get
mix test
mix tck --group 0001-input-data-string --report artifacts/tck-results.csv
```

`mix test` runs ExUnit and the strict, targeted FEEL `implemented` profile.
FEEL and DMN selections are distinct: use `--suite feel` for FEEL-focused
groups and `--suite dmn` for DMN-focused groups. Cases outside an implemented
profile are counted as disabled rather than executed.

Run complete suite snapshots explicitly:

```bash
mix tck --suite feel --all --soft-fail
mix tck --suite dmn --all --soft-fail
```
