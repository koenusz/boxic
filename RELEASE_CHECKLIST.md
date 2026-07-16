# Release checklist

Use this checklist independently for `boxic_feel` and `boxic_dmn` releases.

- [ ] `mix format --check-formatted`, `mix compile --warnings-as-errors`, and `mix test` pass.
- [ ] `bash scripts/verify_tck_pin.sh` confirms the vendored corpus and pinned commit.
- [ ] Both implemented profiles pass without failed, errored, missing, or unsupported entries.
- [ ] `scripts/check_tck_regression.exs` passes against the tracked FEEL and DMN baselines.
- [ ] Fresh CSV and JSON reports are retained with the release artifacts.
- [ ] Release notes identify the DMN TCK commit and DMN specification version.
- [ ] Release notes list newly supported groups and known unsupported groups.
- [ ] Compatibility delta reports are generated for both suites, for example:

      mix run scripts/tck_compatibility_delta.exs previous-feel.json current-feel.json --output feel-delta.md
      mix run scripts/tck_compatibility_delta.exs previous-dmn.json current-dmn.json --output dmn-delta.md

- [ ] Package versions and `boxic_dmn`'s compatible `boxic_feel` dependency range are correct.
- [ ] Any semantic breaking changes are called out explicitly.
