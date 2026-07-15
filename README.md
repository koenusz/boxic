# Arbiter

Arbiter is an Elixir umbrella project for FEEL and DMN engines with an internal
DMN TCK harness.

## Apps

- `arbiter_feel`: FEEL parsing and evaluation API.
- `arbiter_dmn`: DMN model loading and decision evaluation using FEEL.
- `arbiter_dmn_tck`: Internal TCK discovery, execution, and reporting.

## Iteration A status

- umbrella scaffolding complete;
- local vendored TCK fixture corpus under `vendor/dmn-tck`;
- native Elixir TCK runner with explicit statuses;
- machine-readable CSV and JSON report generation;
- one end-to-end literal-expression case passing.

## Commands

```bash
mix deps.get
mix test
mix tck --profile core --report artifacts/tck-results.csv
```

