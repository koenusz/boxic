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
`implemented` profile. The tracked strict baselines currently pass 2,042 FEEL
entries, explicitly report all 18 Java-external-function entries as unsupported
on the Elixir runtime, and pass 77 DMN entries against the pinned corpus.

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

## Java external functions and the Elixir replacement

The strict FEEL profile includes all 18 entries in the official
`0076-feel-external-java` group and reports each one as `unsupported`. These
cases exercise DMN functions declared with `kind="Java"` or FEEL expressions
such as `function(...) external {java: {...}}`. They require Java class lookup,
Java method-signature resolution, JVM primitive conversions, and reflective
method invocation.

Arbiter runs on the BEAM and does not embed a JVM or provide a Java reflection
bridge. Arbiter therefore provides an allowlisted Elixir external-function
registry as the platform-native replacement for this integration capability.
It serves the same application-level purpose—calling trusted host-language code
from FEEL and DMN—but it cannot satisfy a test that specifically requires Java
reflection. Arbiter consequently keeps the conformance result and the useful
replacement feature separate:

- the 18 entries are selected and visible in strict reports rather than being
  disabled or skipped;
- they do not count as passing or supported coverage;
- they do not reduce compatibility on Arbiter's supported scope; and
- incidental parser or expected-error behavior cannot be mistaken for partial
  Java interoperability.

The Elixir replacement supports compile-time registration, typed argument and
return conversion, variadic calls, built-in shadowing, structured host errors,
and explicit injection into DMN evaluation. Model text can invoke registered
names but cannot select arbitrary modules or functions. Usage instructions and
complete examples are in the
[Arbiter FEEL README](../arbiter_feel/README.md#elixir-external-functions).

Supporting the Java group itself in the future would still require an explicit
JVM adapter with a documented trust boundary, class and method allowlisting,
signature and value conversion rules, and deterministic error behavior. Until
such an adapter exists, Java external functions remain intentionally outside
Arbiter's supported platform contract.

CI regenerates both strict reports and compares compatibility, suite coverage,
pass counts, and the pinned TCK revision with the tracked baselines. The
scheduled nightly workflow additionally runs the complete corpus in diagnostic
mode and retains CSV/JSON artifacts for 30 days. Release preparation and delta
commands are documented in `RELEASE_CHECKLIST.md` at the repository root.
