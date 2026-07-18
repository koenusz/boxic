# Hex release readiness plan

This document tracks the work required to publish `boxic_feel` and `boxic_dmn`
to Hex. The package-specific release procedure remains in
[`RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md).

## Status

- [x] Complete the initial code-quality and Hex-readiness review.
- [x] Make the TCK regression gate expect the 18 Java-specific unsupported
      FEEL cases.
- [ ] Complete licensing and repository identity (files and CI complete;
      ownership and public-repository checks remain).
- [x] Configure both Hex packages.
- [x] Refactor the main FEEL and DMN modules.
- [x] Complete public API documentation.
- [x] Add static quality and package CI gates.
- [ ] Pass clean-consumer smoke tests.
- [ ] Publish `boxic_feel` 0.1.0.
- [ ] Publish `boxic_dmn` 0.1.0.

## Decisions

### License

Use the Apache License, Version 2.0, with SPDX identifier `Apache-2.0`, for
both `boxic_feel` and `boxic_dmn`.

Reasons:

- It permits commercial and closed-source use.
- It includes an explicit contributor patent grant and patent-termination
  clause, which is useful for a standards implementation.
- It aligns with the separately vendored DMN TCK license, although Boxic is
  not required to use the same license.
- Hex accepts `Apache-2.0` as a package license identifier.

Before applying the license, confirm the correct legal person or company to
name as the copyright holder and confirm that no employer or previous
contributor has competing ownership rights.

### Package order

Publish `boxic_feel` before `boxic_dmn`. The published `boxic_dmn` package must
depend on a compatible Hex version of `boxic_feel`; it must not ship with an
`in_umbrella` or path-only dependency.

## WP-00: Land the TCK regression policy

- [x] Use the tracked baseline as the expected unsupported count.
- [x] Require the exact unsupported case identities recorded in the baseline.
- [x] Permit the 18 `0076-feel-external-java` cases for FEEL.
- [x] Require zero unsupported cases for DMN.
- [x] Add regression tests for count changes and same-count case substitution.
- [x] Update the nightly and CI workflow labels.
- [x] Update the release checklist.
- [ ] Commit and merge the TCK regression changes.
- [ ] Confirm CI and the nightly workflow pass on the merged commit.

### Acceptance criteria

- FEEL reports 2,042 passing and exactly 18 known unsupported entries, with no
  failed, errored, or missing entries.
- DMN reports 1,485 passing entries, with no unsupported, failed, errored, or
  missing entries.

## WP-01: Licensing and repository identity

- [ ] Confirm the Boxic copyright holder.
      Blocked pending confirmation of the exact legal person or company name;
      Git metadata alone is not sufficient legal confirmation.
- [x] Add the unmodified Apache-2.0 license text as `/LICENSE`.
- [x] Add identical license files to `apps/boxic_feel/LICENSE` and
      `apps/boxic_dmn/LICENSE`.
- [x] Add `THIRD_PARTY_NOTICES.md`.
- [x] Document the vendored DMN TCK project, upstream licensing notices, and
      pinned revision in the third-party notice.
- [x] State that the TCK corpus is not included in either Hex package.
- [x] Add a CI check that the three Boxic license files remain identical.
- [ ] Make the canonical source repository publicly accessible.
- [ ] Confirm all package links work without authentication.
      Both repository items are blocked locally: GitHub currently returns 404
      for the configured repository and the available `gh` credential is
      invalid.

### Acceptance criteria

- The repository and both package tarballs contain an unambiguous
  Apache-2.0 license.
- Third-party source and license information remains clearly separated from
  Boxic's own license.

## WP-02: Hex package configuration

### `boxic_feel`

- [x] Add a package description.
- [x] Add `package/0` with an explicit file list.
- [x] Set `licenses: ["Apache-2.0"]`.
- [x] Add repository, changelog, and documentation links.
- [x] Add `source_url` and `homepage_url`.
- [x] Confirm version `0.1.0`.

Recommended description:

> A native Elixir parser and evaluator for the Friendly Enough Expression
> Language defined by DMN.

### `boxic_dmn`

- [x] Add a package description.
- [x] Add `package/0` with an explicit file list.
- [x] Set `licenses: ["Apache-2.0"]`.
- [x] Add repository, changelog, and documentation links.
- [x] Add `source_url` and `homepage_url`.
- [x] Confirm version `0.1.0`.
- [x] Replace the publish-time `in_umbrella` dependency with a compatible Hex
      requirement on `boxic_feel`.

Recommended description:

> A native Elixir loader, validator, and evaluator for Decision Model and
> Notation 1.4 models.

### Package contents

Use a deliberate package file list equivalent to:

```elixir
~w(lib mix.exs README.md LICENSE CHANGELOG.md)
```

- [x] Ensure the vendored TCK corpus is excluded.
- [x] Ensure tests, compatibility reports, planning documents, and local
      artifacts are excluded.
- [x] Add a deterministic release-staging task or script for converting the
      local umbrella dependency into a Hex dependency without modifying the
      working tree.
- [x] Build and inspect the unpacked `boxic_feel` package.
- [x] Build and inspect the unpacked `boxic_dmn` package.
- [x] Confirm the `boxic_dmn` package metadata lists `boxic_feel`.

### Acceptance criteria

- `mix hex.build --unpack` succeeds for both applications.
- Each archive contains only the intended runtime, documentation, and license
  files.
- Hex recognizes every production dependency.

## WP-03: Public API and internal structure

Keep `Boxic.FEEL` and `Boxic.DMN` as stable public facades while extracting
their internal responsibilities.

### FEEL

- [x] Extract tokenization from `Boxic.FEEL`.
- [x] Extract parsing from `Boxic.FEEL`.
- [x] Extract evaluation from `Boxic.FEEL`.
- [x] Extract semantic comparison and operator helpers where useful.
- [x] Preserve the existing public FEEL entry points.

Candidate modules:

- `Boxic.FEEL.Tokenizer`
- `Boxic.FEEL.Parser`
- `Boxic.FEEL.Evaluator`
- `Boxic.FEEL.Semantics`

### DMN

- [x] Extract XML loading and normalization from `Boxic.DMN`.
- [x] Extract validation from `Boxic.DMN`.
- [x] Extract decision evaluation from `Boxic.DMN`.
- [x] Extract decision-table evaluation.
- [x] Extract import discovery and resolution.
- [x] Preserve the existing public DMN evaluation entry points.

Candidate modules:

- `Boxic.DMN.XML.Loader`
- `Boxic.DMN.Validator`
- `Boxic.DMN.Evaluator`
- `Boxic.DMN.DecisionTable`
- `Boxic.DMN.Imports`

### API cleanup

- [x] Add explicit file and XML loading functions such as `load_file/1` and
      `parse/1` or `load_xml/1`.
- [x] Return a file error for a missing path instead of `:invalid_xml`.
- [x] Preserve malformed or unreadable import errors instead of silently
      discarding imported models.
- [x] Decide which normalized model structs are public API. The normalized
      `Boxic.DMN.Model` structs returned by the loaders remain public.
- [x] Fully specify the types of public structs.
- [x] Mark internal model representations opaque or private where appropriate.
      No normalized model structs are internal: they are the documented return
      value of the public loaders, so they intentionally remain transparent.
- [x] Replace broad `term()` error specifications with documented error types.
- [x] Remove `BoxicFeel.hello/0`.
- [x] Remove `BoxicDmnTck.hello/0`.
- [x] Remove internal work-package language from public module documentation.

### Acceptance criteria

- Public facade compatibility tests pass.
- FEEL and DMN TCK results do not regress.
- The main public modules primarily delegate to focused internal modules.
- File, XML, validation, import, and evaluation errors are distinguishable.

## WP-04: Package documentation

### Tooling

- [x] Add ExDoc as a development-only dependency to `boxic_feel`.
- [x] Add ExDoc as a development-only dependency to `boxic_dmn`.
- [x] Configure the main page, source URL, version reference, module groups,
      and guides for each package.
- [x] Run documentation builds with warnings treated as errors.

### Public API

- [x] Add `@doc` documentation and examples to every intended public FEEL
      function.
- [x] Add `@doc` documentation and examples to every intended public DMN
      function.
- [x] Document result and error contracts.
- [x] Document public types and structs.
- [x] Remove `WP-06`, `WP-08`, and similar internal planning references from
      public documentation.

### Package READMEs and guides

- [x] Rewrite `apps/boxic_feel/README.md` as a standalone package README.
- [x] Rewrite `apps/boxic_dmn/README.md` as a standalone package README.
- [x] Remove the DMN README placeholder.
- [x] Add installation and quick-start examples.
- [x] Document the supported DMN specification version.
- [x] Document the TCK compatibility result and its scope.
- [x] Document the intentional Java integration limitation.
- [x] Document the external-function trust boundary.
- [x] Ensure package-authored documentation links reference only included or
      public resources. Visibility of generated source links remains tracked
      separately under WP-01 and WP-07.
- [x] Add `CHANGELOG.md` to each package.

### Acceptance criteria

- `mix docs --warnings-as-errors` succeeds independently for both packages.
- A new user can install and use either package using only the documentation
  shipped in that package.

## WP-05: Static quality and CI gates

- [x] Add Credo and agree on a checked configuration.
- [x] Add Dialyxir and establish a clean baseline.
- [x] Add coverage reporting with a realistic initial threshold (40% FEEL,
      50% DMN; measured baselines are 43.43% and 54.47%).
- [x] Run formatting checks in CI.
- [x] Compile with warnings as errors in CI.
- [x] Run unit tests in CI.
- [x] Run the strict FEEL and DMN profiles in CI.
- [x] Run compatibility regression gates in CI.
- [x] Run Credo in CI.
- [x] Run Dialyzer in CI.
- [x] Build documentation with warnings as errors in CI.
- [x] Run the Hex dependency retirement audit in CI.
- [x] Build both Hex packages in CI.
- [x] Inspect package metadata and contents in CI.
- [x] Test the minimum supported Elixir/OTP combination.
- [x] Test the latest supported Elixir/OTP combination.

### Acceptance criteria

- All quality and publication checks run from a documented command or CI job.
- No required release behavior exists only on a maintainer's machine.

## WP-06: Clean-consumer smoke tests

### `boxic_feel`

- [ ] Create a fresh temporary Mix project.
- [ ] Install the locally built `boxic_feel` tarball.
- [ ] Fetch and compile its dependencies.
- [ ] Evaluate a basic expression successfully.

Example assertion:

```elixir
{:ok, value} = Boxic.FEEL.evaluate("1 + 2")
```

### `boxic_dmn`

- [ ] Create a second fresh temporary Mix project.
- [ ] Install the locally built `boxic_dmn` tarball.
- [ ] Confirm `boxic_feel` resolves transitively.
- [ ] Load, validate, and evaluate a small DMN model.
- [ ] Confirm no umbrella-relative paths are required.
- [ ] Confirm no TCK, test, or compatibility files are installed.

### Acceptance criteria

- Both packages work from their actual release archives in projects outside
  the Boxic repository.

## WP-07: First publication

- [ ] Reconfirm that the `boxic_feel` and `boxic_dmn` package names are
      available.
- [ ] Confirm the source repository and documentation links are public.
- [ ] Confirm the Hex account, package ownership, two-factor authentication,
      and publication key are ready.
- [ ] Run every item in `RELEASE_CHECKLIST.md` on the exact release commit.
- [ ] Inspect both final unpacked tarballs.
- [ ] Publish `boxic_feel` 0.1.0.
- [ ] Install `boxic_feel` from Hex in a clean external project.
- [ ] Verify the `boxic_feel` HexDocs site.
- [ ] Publish `boxic_dmn` 0.1.0.
- [ ] Install `boxic_dmn` from Hex in a clean external project.
- [ ] Verify the `boxic_dmn` HexDocs site.
- [ ] Create package-specific Git tags.
- [ ] Create GitHub release notes.
- [ ] Record the DMN specification version and TCK commit in both changelogs.

## Definition of done

- [x] Apache-2.0 licensing is present in the repository and both packages.
- [x] Both Hex package builds succeed without warnings.
- [ ] `boxic_dmn` has a resolvable Hex dependency on `boxic_feel`.
- [ ] HexDocs builds without warnings.
- [ ] Package-specific READMEs and changelogs are complete.
- [ ] No scaffold or internal work-package language remains in public modules.
- [ ] Static analysis and all tests pass.
- [ ] FEEL reports exactly the 18 known Java cases as unsupported.
- [ ] DMN reports zero unsupported cases.
- [ ] Fresh external projects can install and execute both release archives.
- [ ] Package metadata, public links, versions, tags, and release notes agree.
