# Release checklist

Use this checklist independently for `boxic_feel` and `boxic_dmn` releases.
Track the broader publication-readiness work in
[`HEX_RELEASE_READINESS_PLAN.md`](HEX_RELEASE_READINESS_PLAN.md).

## Quality gates

Run the static checks from the umbrella root:

```bash
mix quality
mix hex.audit
```

Run coverage and documentation independently for each publishable package:

```bash
(cd apps/boxic_feel && mix test --cover && mix docs --warnings-as-errors)
(cd apps/boxic_dmn && mix test --cover && mix docs --warnings-as-errors)
```

The initial measured coverage floors are 40% for `boxic_feel` and 50% for
`boxic_dmn`. Raise them as focused tests improve; do not lower them to
accommodate a regression.

Build and inspect both staged archives:

```bash
mix run scripts/build_hex_package.exs boxic_feel /tmp/boxic_feel.tar
mix run scripts/build_hex_package.exs boxic_dmn /tmp/boxic_dmn.tar
mix run scripts/inspect_hex_package.exs boxic_feel /tmp/boxic_feel.tar
mix run scripts/inspect_hex_package.exs boxic_dmn /tmp/boxic_dmn.tar
mix run scripts/smoke_test_hex_packages.exs \
  /tmp/boxic_feel.tar /tmp/boxic_dmn.tar
```

Both packages support Elixir 1.20.x. CI tests the lower supported OTP boundary
on Elixir 1.20.0 / OTP 27.3 and the project toolchain on Elixir 1.20.0 /
OTP 29.0.1.

## Release checks

- [x] `mix format --check-formatted`, `mix compile --warnings-as-errors`, and `mix test` pass.
- [x] Staged Hex package builds succeed:

      mix run scripts/build_hex_package.exs boxic_feel /tmp/boxic_feel.tar
      mix run scripts/build_hex_package.exs boxic_dmn /tmp/boxic_dmn.tar

- [x] Both staged packages pass the clean-consumer smoke test.
- [x] `bash scripts/verify_tck_pin.sh` confirms the vendored corpus and pinned commit.
- [x] Both implemented profiles pass without failed, errored, or missing entries.
- [x] The FEEL profile reports exactly the 18 known unsupported cases from
      `0076-feel-external-java`; the DMN profile reports zero unsupported cases.
- [x] `scripts/check_tck_regression.exs` passes against the tracked FEEL and DMN baselines.
- [x] Fresh CSV and JSON reports are retained with the release artifacts.
- [x] Release notes identify the DMN TCK commit and DMN specification version.
- [x] Release notes list newly supported groups and known unsupported groups.
- [x] Compatibility delta reports are generated for both suites, for example:

      mix run scripts/tck_compatibility_delta.exs previous-feel.json current-feel.json --output feel-delta.md
      mix run scripts/tck_compatibility_delta.exs previous-dmn.json current-dmn.json --output dmn-delta.md

- [x] Package versions and `boxic_dmn`'s compatible `boxic_feel` dependency range are correct.
- [x] Any semantic breaking changes are called out explicitly.
