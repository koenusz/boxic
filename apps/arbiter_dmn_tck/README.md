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

The umbrella `mix test` command follows ExUnit with the strict, targeted FEEL
`implemented` profile. The tracked strict baselines currently pass 1,100 FEEL
entries and 77 DMN entries against the pinned corpus.

FEEL and DMN are selected independently:

```bash
mix tck --suite feel --profile implemented
mix tck --suite dmn --profile implemented
mix tck --suite feel --all --soft-fail
mix tck --suite dmn --all --soft-fail
```

Run a complete, non-blocking compatibility snapshot explicitly:

```bash
mix tck --all --soft-fail --report artifacts/tck-full.csv
```

`--soft-fail` is intended for full-suite visibility while coverage is being
built; direct `mix tck` runs remain strict by default.

Results use the explicit statuses `passed`, `failed`, `unsupported`, `missing`,
and `error`. Unsupported engine behavior must not be counted as passing or
silently skipped.

CI regenerates both strict reports and compares compatibility, suite coverage,
pass counts, and the pinned TCK revision with the tracked baselines. The
scheduled nightly workflow additionally runs the complete corpus in diagnostic
mode and retains CSV/JSON artifacts for 30 days. Release preparation and delta
commands are documented in `RELEASE_CHECKLIST.md` at the repository root.
