# DMN 1.5 capability contract

Boxic DMN 0.3 targets the formally released DMN 1.5 executable profile. The
profile is identified by:

- MODEL: `https://www.omg.org/spec/DMN/20230324/MODEL/`
- FEEL: `https://www.omg.org/spec/DMN/20230324/FEEL/`
- schema root: `DMN15.xsd`

Older, unqualified, and unknown DMN documents may be inspected with
`Boxic.DMN.inspect_xml/1`. They are not promised to validate, execute, or
serialize. Boxic never upgrades or downgrades a document implicitly.

## Public boundaries

- `inspect_xml/1` parses safely and returns a best-effort normalized view. It
  does not confer executable or serialization status.
- `load_xml/1` is a strict DMN 1.5 schema, profile, import, and model boundary.
  It has no filesystem or network authority.
- `load_xml/2` resolves declared imports from an explicit namespace map or
  caller-owned resolver.
- `load_file/1` resolves only declared relative `locationURI` values below the
  root model directory. It never scans siblings or performs network requests.
- `validate/2` independently checks `:evaluation`, `:serialization`, or
  `:authoring` capability and returns `Boxic.DMN.Diagnostic` values.
- `evaluate/4` and `evaluate_service/4` accept trusted BEAM functions through
  an isolated external-function environment.
- `encode_xml/2` emits deterministic DMN 1.5 XML only when the model is known
  to be writable without silent loss.

`load/1` is retained as a compatibility dispatcher for the 0.x transition.
New code should use `load_xml/1`, `load_xml/2`, or `load_file/1`.

## Diagnostics

`Boxic.DMN.Diagnostic` is the stable diagnostic contract for new validation
boundaries. Its categories distinguish XML schema validity, the normalized DMN
model, executable-profile limitations, imports, FEEL, serialization,
evaluation preflight, and evaluation. `Diagnostic.to_map/1` produces a
persistence-safe representation.

The existing `validate/1`, evaluation tuple errors, and
`SerializationError` return shapes remain compatibility edges for this 0.x
release. Downstream consumers that need the new stable contract should use
`validate/2` before evaluation or serialization.

## XML security and runtime requirement

Strict XML input is bounded to 5 MB, 100,000 XML nodes, and 256 nesting levels.
DTDs and entity declarations are rejected before parsing; external entities and
network schema resolution are disabled. Before `xmerl` builds a tree, a SAX
preflight admits only normative schema names plus the finite extension
vocabulary exercised by the pinned TCK, preventing untrusted XML names from
growing the BEAM atom table. Other extension names receive
`:unsupported_xml_name`. Recognized extensions are still fidelity-loss content
and therefore block serialization. Schema diagnostics are truncated.

The packaged OTP `xmerl_xsd` implementation cannot compile the normative DMN
1.5 schema's derivation graph. Boxic therefore invokes `xmllint --nonet` as a
narrow, argument-safe schema adapter and returns
`:schema_validator_unavailable` when it is not installed. The complete schema
family is included in the Hex archive; no schema or instance data is fetched
at runtime.

## Imports

An import must declare the DMN 1.5 MODEL URI as `importType`, provide an exact
namespace match, and resolve to a DMN 1.5 source. File resolution rejects
absolute paths, URI schemes, root escapes, cycles, duplicate namespaces,
missing files, and undeclared ambient documents.

For in-memory XML:

```elixir
Boxic.DMN.load_xml(root_xml,
  imports: %{"urn:example:types" => types_xml}
)
```

A `resolver: fn import -> {:ok, xml_or_model} end` may be supplied instead.
The resolver owns transport, credentials, timeouts, caching, and allowlisting.
It receives no evaluator inputs or external-function environment.

## External functions

Trusted registries are supplied with `external_functions:`. Built-ins win name
collisions by default. A host can explicitly select
`external_function_precedence: :registered`; ordinary model input cannot
replace a built-in or registered callable at a call site. Registry metadata is
not merged into or enumerable from the FEEL input context. Host exceptions are
redacted to a stable public error.

Java reflection and the Java external-function TCK group remain explicitly
unsupported.

## Scope of claims

FEEL evaluation, DMN evaluation, XML schema validation, normalized-model
coverage, import behavior, and writer round trips are independent claims.
Passing the selected evaluator corpus is not evidence of complete DMN XML,
DMNDI, extension, or authoring support. See
`CONSTRUCT_CAPABILITY_LEDGER.md` for the supported interchange surface.
