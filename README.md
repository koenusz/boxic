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
- machine-readable CSV and JSON report generation;
- strict compatibility regression gates and retained nightly full-corpus reports.

Engine compatibility with the official corpus is still in progress. A loaded
test is not treated as passing unless it executes through Arbiter and its
result matches the upstream expected value.

## Commands

```bash
mix deps.get
mix test
mix tck --group 0001-input-data-string --report artifacts/tck-results.csv
```

## Elixir interaction from FEEL and DMN

Arbiter provides an allowlisted Elixir external-function registry as the
BEAM-native replacement for Java external functions. Applications can register
trusted Elixir functions, define FEEL/Elixir value conversions, and inject the
registry into FEEL or DMN evaluation without permitting model text to resolve
arbitrary modules or functions.

See the [external-function guide](apps/arbiter_feel/README.md#elixir-external-functions)
for registry definitions, supported types, variadic functions, FEEL calls, DMN
integration, and security guidance. The Java-specific TCK group remains
explicitly unsupported because this extension provides Elixir integration, not
JVM reflection.

`mix test` runs ExUnit and the strict, targeted FEEL `implemented` profile.
FEEL and DMN selections are distinct: use `--suite feel` for FEEL-focused
groups and `--suite dmn` for DMN-focused groups. Cases outside an implemented
profile are counted as disabled rather than executed.

Run complete suite snapshots explicitly:

```bash
mix tck --suite feel --all --soft-fail
mix tck --suite dmn --all --soft-fail
```

CI compares fresh implemented-profile reports with the tracked compatibility
baselines. The scheduled nightly workflow runs the complete corpus and retains
CSV/JSON artifacts. See [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) for the
release compatibility and delta-report procedure.
