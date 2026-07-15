# Arbiter DMN TCK

Internal, non-published integration harness for the official DMN Technology
Compatibility Kit.

The upstream repository is vendored at the revision recorded in
`vendor/dmn-tck/PINNED_COMMIT`. The loader reads the official namespaced XML
documents under `vendor/dmn-tck/TestCases`; local replacement fixtures are not
part of the compatibility corpus.

Run a focused group from the umbrella root:

```bash
mix tck --group 0001-input-data-string --report artifacts/tck-results.csv
```

The umbrella `mix test` command follows ExUnit with a full `mix tck --all
--soft-fail` summary. `--soft-fail` is intended for visibility while coverage
is being built; direct `mix tck` runs remain strict by default.

Results use the explicit statuses `passed`, `failed`, `unsupported`, `missing`,
and `error`. Unsupported engine behavior must not be counted as passing or
silently skipped.
