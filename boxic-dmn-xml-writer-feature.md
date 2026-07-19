# Boxic DMN XML Writer

Status: `release-ready`

Target package: `boxic_dmn`

Initial target: `boxic_dmn` 0.2.0

## Summary

Add a standards-oriented XML writer to `boxic_dmn` that serializes a
`Boxic.DMN.Model` into valid, deterministic DMN XML.

The writer completes the package's bidirectional document boundary:

```text
DMN XML
   │
   ▼
Boxic.DMN.load_xml/1
   │
   ▼
Boxic.DMN.Model
   │
   ▼
Boxic.DMN.encode_xml/2
   │
   ▼
DMN XML
```

The primary first use case is visual decision-table authoring. Applications
must be able to load a standard `.dmn` document, edit its normalized decision
table, serialize the result, validate it, persist it as a versioned artifact,
and export it to other DMN-compatible tools.

The writer belongs in `boxic_dmn` because it serializes Boxic's public,
normalized representation of the standard DMN metamodel. UI selection state,
incomplete form rows, undo stacks, sample evaluation data, and persistence
workflows remain application concerns.

## Release Goal

The 0.2 release enables a decision-table UI, implemented in another project,
to use `boxic_dmn` as its document and semantic boundary:

1. load a DMN document into `Boxic.DMN.Model`;
2. edit a decision table through a small, invariant-preserving authoring API;
3. validate the edited model;
4. encode the complete model back to shareable standard DMN XML; and
5. reload and evaluate the encoded document with equivalent semantics.

The writer must serialize the complete supplied model, including dependencies
needed by an edited decision table. The authoring API in 0.2 is intentionally
focused on decision-table editing. A comprehensive API for constructing every
DMN metamodel value from scratch is not required for this release.

## Motivation

`boxic_dmn` 0.1.0 supports loading, validating, and evaluating DMN models, but
it does not provide the reverse normalized-model-to-XML operation. Without that
operation, consumers that visually author DMN must choose between:

- maintaining a second proprietary decision-table model;
- constructing XML themselves;
- editing raw XML only;
- patching the original XML tree while separately maintaining the normalized
  model;
- losing standard `.dmn` import/export and round-trip guarantees.

Each alternative splits DMN syntax ownership between the package and its
consumers. A package-owned writer centralizes namespaces, element names,
attributes, references, escaping, ordering, unsupported-content detection, and
standards validation.

## Design Principles

### Standards-oriented

The output must be standard DMN XML for the DMN version pinned by the Boxic
project. Do not introduce a Boxic-only XML vocabulary for ordinary DMN
elements.

### Version-aligned

The writer must not hardcode a DMN version, model namespace, schema location,
or TCK revision.

Boxic must have one shared compatibility profile that is the source of truth
for:

- the project's pinned DMN specification version;
- the DMN model namespace;
- related namespace and schema identifiers;
- the vendored normative XSD revision;
- the vendored TCK revision;
- the normalized element/expression profile supported for that version.

The loader, validator, evaluator compatibility tests, writer, schema tests, and
package documentation must all consume this profile. The writer must not keep
a parallel copy of these values.

The exact module/API name should follow the library's existing compatibility
organization. Conceptually, the boundary provides values such as:

```elixir
profile = Boxic.DMN.Compatibility.pinned_profile()

profile.version
profile.model_namespace
profile.schemas
profile.tck_revision
```

These names are illustrative rather than a required public API.

`encode_xml/2` emits the pinned version. If a normalized model records a source
DMN version/profile that differs from the project pin, serialization fails with
`:dmn_version_mismatch`. The writer must never silently upgrade or downgrade a
model.

If the normalized model does not currently retain its source version, the
model audit must determine whether the loader already rejects every non-pinned
namespace. If it does not, add explicit source-version/profile metadata at the
loading boundary.

Supporting multiple output versions is a future compatibility feature. It
requires registered version profiles plus explicit, tested model conversion;
it must not be implemented as an arbitrary namespace or version-string option.

### Semantic round-trip

The writer guarantees semantic, not byte-identical, round-tripping.

Given a supported model:

```elixir
{:ok, first_model} = Boxic.DMN.load_xml(input_xml)
:ok = Boxic.DMN.validate(first_model)

{:ok, output_xml} = Boxic.DMN.encode_xml(first_model)

{:ok, second_model} = Boxic.DMN.load_xml(output_xml)
:ok = Boxic.DMN.validate(second_model)
```

`first_model` and `second_model` must have equivalent normalized semantics.
Their XML may differ in:

- indentation;
- namespace prefixes;
- attribute ordering;
- XML declaration presence when selected through an option;
- insignificant whitespace;
- CDATA versus escaped text representation.

Evaluation of the same named decisions and decision services with the same
inputs must produce equivalent results before and after the round-trip.

### Loss-safe

The writer must never silently discard model content.

If the normalized model contains an unsupported expression, extension,
reference, metadata value, or loader issue that prevents faithful
serialization, writing must fail with structured errors. A consumer may not
receive apparently valid XML that has different business semantics.

### Deterministic

The same normalized model and writer options must produce the same bytes across
repeated calls on the same Boxic release. Deterministic output enables stable
checksums and source-control diffs.

### Pure

The primary API returns XML. It does not write files, mutate the model, access
application configuration, generate random identifiers, or resolve remote
imports.

## Public API

Add the writer to the existing public facade:

```elixir
@spec encode_xml(Boxic.DMN.Model.t(), keyword()) ::
        {:ok, String.t()} | {:error, [Boxic.DMN.SerializationError.t()]}
def encode_xml(model, opts \\ [])
```

Example:

```elixir
with {:ok, model} <- Boxic.DMN.load_xml(xml),
     :ok <- Boxic.DMN.validate(model),
     {:ok, written_xml} <- Boxic.DMN.encode_xml(model, format: :pretty),
     {:ok, written_model} <- Boxic.DMN.load_xml(written_xml),
     :ok <- Boxic.DMN.validate(written_model) do
  {:ok, written_xml}
end
```

Supported initial options:

```elixir
[
  format: :pretty | :compact,
  xml_declaration: boolean()
]
```

Defaults:

```elixir
[
  format: :pretty,
  xml_declaration: true
]
```

Both formats must be deterministic. `:pretty` uses two-space indentation, LF
line endings, UTF-8, and one final newline. `:compact` removes presentation
indentation but preserves expression text and other semantically significant
text.

Do not call either format XML canonicalization unless the implementation
actually conforms to an established XML canonicalization specification.
Deterministic Boxic output is sufficient for this feature.

An optional preflight API may be exposed when it materially improves consumer
error handling:

```elixir
@spec validate_serializable(Boxic.DMN.Model.t(), keyword()) ::
        :ok | {:error, [Boxic.DMN.SerializationError.t()]}
def validate_serializable(model, opts \\ [])
```

`encode_xml/2` must always run the same checks, so preflight is a convenience
rather than a required safety step.

An exception-raising `encode_xml!/2` is not required for the first release. If
added later, it must wrap the structured error result rather than implement a
separate writing path.

`write_file/3` is intentionally out of scope. Filesystem persistence is a
caller concern and does not add DMN semantics.

## Error Model

Add a public structured error:

```elixir
defmodule Boxic.DMN.SerializationError do
  @enforce_keys [:code, :path, :message]

  defstruct [
    :code,
    :path,
    :message,
    :details
  ]

  @type t :: %__MODULE__{
          code: atom(),
          path: [String.t() | non_neg_integer()],
          message: String.t(),
          details: term()
        }
end
```

`path` identifies the normalized model location rather than an XML line that
does not exist yet. Examples:

```elixir
%Boxic.DMN.SerializationError{
  code: :unsupported_expression,
  path: ["decisions", "eligibility", "expression"],
  message: "Decision eligibility contains an unsupported expression.",
  details: %{expression: "vendorExpression"}
}

%Boxic.DMN.SerializationError{
  code: :rule_entry_count_mismatch,
  path: ["decisions", "eligibility", "expression", "rules", 3],
  message: "Rule has 1 input entry but the table declares 2 input clauses.",
  details: %{expected: 2, actual: 1}
}
```

Initial error codes should cover at least:

- `:invalid_model`;
- `:dmn_version_mismatch`;
- `:missing_required_value`;
- `:invalid_identifier`;
- `:duplicate_identifier`;
- `:unresolved_reference`;
- `:unsupported_expression`;
- `:unsupported_extension`;
- `:lossy_serialization`;
- `:rule_entry_count_mismatch`;
- `:invalid_hit_policy`;
- `:invalid_aggregation`;
- `:invalid_option`;
- `:xml_encoding_failed`.

Errors must be safe to inspect. They must not include evaluation contexts,
external-function configuration, or unrelated application data.

## Required First-Release Model Surface

The first public writer release must serialize the complete normalized model
surface supported by the pinned Boxic loader, validator, and evaluator. A
decision-table-only writer is insufficient: decision services can expose
multiple decisions and depend on business knowledge models, invocations,
imports, item definitions, and other boxed expressions. Applications must not
require a second Boxic upgrade to serialize a model they can already load and
evaluate.

### Definitions and DRG elements

Support:

- definitions metadata;
- imports;
- item definitions and recursive item components;
- input data and variables;
- decisions and decision variables;
- information requirements;
- knowledge requirements and authority requirements represented by the model;
- business knowledge models;
- decision services, including input data, input decisions, output decisions,
  and encapsulated decisions where represented by the normalized model;
- every normalized binding, parameter, variable, and reference required by
  those elements.

### Expressions

Serialize every normalized expression supported by evaluation:

- literal expressions;
- decision tables;
- boxed contexts and ordered context entries;
- invocations and named bindings;
- function definitions and parameters;
- relations, columns, and rows;
- lists;
- conditional expressions;
- filters;
- iterators;
- any additional expression added to the pinned evaluator profile before the
  writer release.

The compatibility-profile consistency test must fail if the evaluator registers
a normalized expression type that the writer does not handle.

`{:unsupported, expression_name}` is not a supported normalized expression. It
represents content that the package could not normalize faithfully and must
produce a structured lossy/unsupported error.

### Decision tables

Support the complete 0.2 semantic decision-table surface:

- input and output clauses;
- ordered rules;
- hit policy and aggregation;
- input expressions;
- input and output allowed values;
- default output entries;
- input entries as FEEL unary-test text;
- output entries as FEEL expression text;
- standard labels and output labels.

Descriptions, documentation, rule annotation clauses, and ordered annotation
entries belong to the preservation profile. They are serialized only if the
0.2 model is extended to retain them; otherwise their presence produces a
fidelity issue that blocks serialization.

### Preservation surface

For 0.2, distinguish the following surfaces:

- **Semantic writer profile:** every normalized DRG element and expression
  currently supported by the pinned loader, validator, and evaluator. The
  writer must serialize this complete profile.
- **Preservation profile:** authored-document content retained by the loader
  even though it is not evaluated, such as descriptions, documentation,
  decision-table annotations, extensions, and DMNDI.
- **Rejected profile:** content the loader cannot normalize or preserve
  faithfully. A model containing such content must not be presented as a safe
  round-trip.

The 0.2 writer is complete for the semantic writer profile. It preserves
preservation-profile content only where the 0.2 loader and normalized model
explicitly retain it. Otherwise the loading boundary must record a fidelity
issue and serialization must reject the model rather than silently discard the
content. Full structured preservation of arbitrary extensions and DMNDI is
deferred.

The writer serializes the full supplied model. It must not select one decision,
one service, or one table and omit the rest of the definitions document.

## Current Normalized Model Assessment

The existing model already contains the essential decision-table semantics:

```elixir
%Boxic.DMN.Model.DecisionTable{
  id: nil,
  hit_policy: nil,
  aggregation: nil,
  output_label: nil,
  inputs: [],
  outputs: [],
  rules: []
}
```

Its supporting values include:

```elixir
%Boxic.DMN.Model.InputClause{
  id: nil,
  label: nil,
  expression: nil,
  type_ref: nil,
  allowed_values: nil
}

%Boxic.DMN.Model.OutputClause{
  id: nil,
  label: nil,
  name: nil,
  type_ref: nil,
  allowed_values: nil,
  default_output: nil
}

%Boxic.DMN.Model.DecisionRule{
  id: nil,
  input_entries: [],
  output_entries: []
}
```

Before implementation, compare the complete normalized model against the
metamodel and XML schema selected by the project's pinned DMN compatibility
profile. Determine whether the current model preserves every standard semantic
value needed for the 0.2 semantic writer profile.

Audit and, where necessary, extend:

- decision-table preferred orientation;
- rule annotation clauses and annotation entries;
- element labels and output labels;
- namespace-qualified type references;
- import namespace, location, and import type;
- item-definition component ordering;
- loader issues representing duplicate or unsupported content;
- the `{:unsupported, name}` expression representation.

Add source-profile and serialization-fidelity metadata to the model. The loader
must record discarded descriptions/documentation, annotations, extension
content, DMNDI, unknown elements, and unknown attributes as fidelity issues
until those values have a namespace-aware normalized representation. The
writer must reject such a model with structured errors.

All semantic and provenance data required for a safe 0.2 round-trip belongs in
`Boxic.DMN.Model`, not in a consumer-specific shadow model.

UI-only state does not belong in the normalized model. Examples include:

- selected or focused cell;
- temporary client row keys;
- open/closed panels;
- dirty flags;
- validation-message visibility;
- undo/redo stacks;
- sample evaluation inputs;
- autosave timestamps.

## Fidelity and Unsupported Content

### Required rule

If loading discarded information that the writer would need to reproduce
business semantics, the loaded model must retain enough provenance to prevent a
false successful round-trip.

The current model's `issues` collection may provide part of this signal.
Implementation must define which loader issues block serialization.

If issues alone cannot distinguish harmless normalization from content loss,
extend the normalized model with an explicit representation such as:

```elixir
serialization_fidelity: :complete | {:lossy, [term()]}
```

or retain unsupported standard/extension nodes in a structured form. The exact
shape should fit the existing model architecture, but successful serialization
must mean that the package knows it has not silently dropped semantics.

### Unsupported expressions

`{:unsupported, expression_name}` cannot be serialized faithfully because it
does not contain the original subtree. `encode_xml/2` must return
`:unsupported_expression` or `:lossy_serialization` for such a model.

### Extensions

When extension elements and attributes are supported by the preservation
profile, preserve them as namespace-aware normalized values and write them back
without interpreting vendor semantics. The representation must retain:

- namespace URI and local name;
- qualified attributes;
- ordered child elements and text;
- the relative position required to reproduce the extension container.

Prefix spelling may be normalized as long as namespace identity and extension
content are preserved. In 0.2, an extension that cannot be represented safely
must cause the loader to mark serialization fidelity as lossy, and
`encode_xml/2` must reject it. Silently omitting extensions is prohibited.

### Layout

DMNDI/DRD layout is distinct from decision logic but is part of an authored DMN
artifact. The 0.2 loader must detect layout content that it does not retain and
mark the model as lossy for serialization. `encode_xml/2` must reject that
model rather than return XML that silently destroys diagram positions,
dimensions, waypoints, labels, or styles.

Structured DMNDI preservation and editing are deferred until the normalized
layout model is designed. Applications may create and share 0.2 models without
layout.

## Identifier Policy

The writer must not generate random identifiers.

- Required missing identifiers produce structured errors.
- Optional absent identifiers are omitted.
- Existing identifiers are preserved.
- Map keys and embedded element ids must agree where both represent the same
  identity; disagreement produces an error.
- Duplicate identifiers produce an error.

Identifier creation is an authoring concern and must not occur implicitly
during serialization. The focused decision-table authoring API accepts
caller-provided stable IDs. A deterministic derivation helper may be included
only if its algorithm and cross-release stability are documented and tested.

## Decision-Table Authoring API

The writer accepts complete normalized models; it must not also mutate or
repair them. A UI could update public structs and lists directly, but several
common table operations affect multiple values at once. For example, adding an
input clause requires adding one input entry to every existing rule, and
removing an output clause requires removing the corresponding output entry from
every rule.

Add a small immutable authoring boundary focused on these cross-structure
invariants. It operates on the same normalized structs used by the loader,
validator, evaluator, and writer.

The 0.2 API must support at least:

- locating a decision table by stable decision ID;
- replacing an individual FEEL input or output entry;
- adding, updating, removing, and moving a rule;
- adding, updating, removing, and moving an input clause while keeping rule
  input-entry arity aligned;
- adding, updating, removing, and moving an output clause while keeping rule
  output-entry arity aligned;
- changing the hit policy and aggregation;
- changing allowed values and default output entries;
- preserving all unaffected model values and list ordering.

The API must:

- return `{:ok, updated_model}` or structured authoring errors;
- accept explicit stable ids;
- never use randomness, timestamps, process ids, or global mutable counters;
- preserve list ordering;
- reject missing decisions, non-table decisions, duplicate IDs, invalid
  positions, and row/column arity violations;
- permit temporarily invalid FEEL text because a UI needs to represent text
  while the user is editing, while structural invariants remain enforced;
- produce the same normalized structs accepted by the loader, validator,
  evaluator, and writer;
- remain independent from UI selection, dirty, focus, undo, and autosave state.

Possible shapes include `Boxic.DMN.Authoring.DecisionTable` or public functions
under a dedicated authoring module:

```elixir
{:ok, model} =
  Boxic.DMN.Authoring.DecisionTable.put_input_entry(
    model,
    decision_id: "eligibility",
    rule_id: "rule_3",
    input_id: "customer_age",
    text: ">= 18"
  )

{:ok, model} =
  Boxic.DMN.Authoring.DecisionTable.add_output(
    model,
    decision_id: "eligibility",
    output: %Boxic.DMN.Model.OutputClause{
      id: "explanation",
      name: "Explanation",
      type_ref: "string"
    },
    entry_text: "\"\""
  )
```

These signatures are illustrative. IDs should be preferred over list indexes
at the public boundary; ordering operations may use explicit target positions.

A comprehensive `Boxic.DMN.Builder` for definitions, imports, BKMs, services,
extensions, DMNDI, and every boxed expression is deferred. It adds little value
to the initial decision-table editing workflow and would substantially expand
the 0.2 public API and test surface.

## Reference Policy

Before emitting XML, validate all references that the writer can resolve from
the supplied model:

- decision information requirements;
- input-data references;
- decision references;
- business-knowledge-model references;
- decision-service input/output/encapsulated decision references;
- imported namespace references;
- item-definition type references where locally resolvable.

References must be serialized using the DMN form expected by the corresponding
element. Do not rewrite a reference merely because a target has a display name.
Stable ids and namespace-qualified names remain distinct.

Remote import fetching and sibling-file discovery are out of scope for the
writer. It serializes already normalized import declarations and model
references.

## Ordering Policy

Ordering must preserve semantics and produce deterministic bytes.

Preserve list order for:

- decision-table input clauses;
- decision-table output clauses;
- decision rules;
- input and output entries within each rule;
- context entries;
- relation columns and rows;
- function parameters;
- item components where order is represented and meaningful.

The top-level normalized model stores several element families in maps. XML
order among independent top-level DRG elements is generally not represented by
those maps. Sort such collections deterministically by stable id, using a
documented secondary key when an id is absent.

Never sort decision rules or table clauses by id or label.

## Decision-Table Validation Before Writing

Serialization validation is stricter than string emission. At minimum:

- a decision table has supported hit-policy and aggregation values;
- aggregation is present only for hit policies where DMN permits it;
- every rule has exactly one input entry per input clause;
- every rule has exactly one output entry per output clause;
- required output names are present for multi-output tables;
- referenced type names are syntactically serializable;
- identifiers are valid and unique;
- FEEL text values are binaries;
- required definition namespace metadata is present;
- unsupported/lossy nodes block output.

Reuse existing `Boxic.DMN.validate/1` rules where appropriate, but keep
serialization-specific validation separate enough to report writer paths and
unsupported-fidelity errors.

The writer does not need to reformat FEEL. Preserve expression and unary-test
source text except for XML escaping. FEEL parsing/validation remains the
responsibility of the existing validation/evaluation boundary.

## XML Generation

### Namespace handling

- Obtain the DMN version, model namespace, and related namespace identifiers
  from the shared pinned compatibility profile.
- Emit the standard namespace URI selected by that profile.
- Use stable, package-owned prefix choices.
- Preserve namespace-qualified type/import references semantically.
- Never derive module names or atoms from namespace values.
- Do not duplicate namespace/version constants in writer modules or tests.
- Reject a model whose recorded source version/profile does not match the
  pinned profile.

### Text and escaping

- Encode UTF-8.
- Escape XML text and attribute values using a single audited implementation.
- Preserve semantically significant FEEL whitespace and string contents.
- Prefer escaped text over CDATA for deterministic output unless CDATA is
  required for a supported construct.
- Reject invalid XML code points.
- Do not interpolate raw XML fragments from expression text, labels, names, or
  descriptions.

### Element emission

Implement serialization as explicit functions per normalized model type rather
than a reflection-based struct dumper. DMN XML element names and nesting do not
always correspond mechanically to Elixir field names.

Suggested internal boundary:

```elixir
Boxic.DMN.XML.Writer.encode(model, opts)
```

Suggested internal organization:

```text
lib/boxic/dmn/xml/writer.ex
lib/boxic/dmn/xml/writer/definitions.ex
lib/boxic/dmn/xml/writer/expressions.ex
lib/boxic/dmn/xml/writer/decision_table.ex
lib/boxic/dmn/serialization_error.ex
```

The exact file split may follow the package's existing loader organization.

Avoid building XML through unconstrained string concatenation. Use an XML
emitter or a small internal element representation that centralizes escaping,
namespace handling, attribute omission, and formatting.

## Deterministic Output Contract

For a fixed Boxic version, model, and options:

- collection ordering follows the ordering policy above;
- attribute order is fixed by writer code;
- namespace prefixes are fixed;
- line endings are LF;
- pretty indentation is two spaces;
- output is UTF-8;
- pretty output has exactly one terminal newline;
- `nil` optional fields are omitted;
- empty standard containers follow one documented representation;
- no timestamps, random ids, process-specific hashes, or environment values are
  inserted.

Add an idempotence test:

```elixir
{:ok, xml_1} = Boxic.DMN.encode_xml(model)
{:ok, model_2} = Boxic.DMN.load_xml(xml_1)
{:ok, xml_2} = Boxic.DMN.encode_xml(model_2)

assert xml_1 == xml_2
```

## Testing Strategy

During implementation, run focused tests for the current work package only.
Examples include the compatibility-profile tests, loader-fidelity tests,
writer unit and round-trip tests, or decision-table authoring tests. Do not run
the complete umbrella suite or full TCK profile after every incremental change.

Before the Hex release, run the complete package and umbrella quality gates,
the applicable full TCK writer profile, schema validation, and the final
release checks. The release is blocked until that full gate passes.

### Unit tests

Test each normalized model type independently:

- required and optional attributes;
- omitted `nil` values;
- identifiers and references;
- namespace-qualified values;
- Unicode;
- XML special characters;
- expression text containing `<`, `>`, `&`, quotes, and newlines;
- list ordering;
- deterministic map ordering;
- compact and pretty formatting;
- every structured error path.

### Decision-table matrix

Cover:

- single-input/single-output tables;
- multiple inputs;
- multiple outputs;
- every supported hit policy;
- collect aggregations;
- allowed input/output values;
- default outputs;
- empty unary tests;
- date, time, datetime, duration, list, context, and numeric FEEL text;
- recursive item definitions;
- information requirements;
- imported type references;
- rule-count and entry-count failures.

### Round-trip tests

For every supported fixture:

1. load original XML;
2. validate the normalized model;
3. serialize it;
4. load the serialized XML;
5. validate the second model;
6. compare canonical semantic projections;
7. evaluate representative decisions with representative contexts;
8. compare evaluation results.

Do not compare model fields that intentionally represent loader provenance or
non-semantic input formatting.

### Schema validation

Validate generated documents against the official XML schema selected by the
project's pinned DMN compatibility profile in a test-only compatibility suite.
Do not require network access during tests; use the reviewed, vendored schema
revision from the existing standards/TCK fixture strategy.

Add a consistency test that fails when the loader, validator, writer, schema
fixture, or TCK configuration resolves a different DMN version/profile.

### TCK reuse

Reuse the vendored official DMN Technology Compatibility Kit corpus:

- serialize every model within the pinned loader/evaluator profile;
- reload serialized output;
- rerun the applicable evaluation cases;
- report unsupported models explicitly rather than counting skipped/lossy
  output as success.

### Property tests

Generate valid normalized definitions across every supported DRG element and
boxed expression, including decision tables and decision services, and assert:

- serialization never raises;
- output reloads successfully;
- normalized semantics round-trip;
- output is deterministic;
- entry ordering is preserved;
- supported preservation-profile values survive;
- models with detected unsupported preservation content are rejected;
- decision-table authoring operations preserve structural invariants;
- authoring output validates, writes, reloads, and evaluates;
- invalid generated structures return errors.

### Security tests

Cover:

- XML markup injection through every text field;
- invalid Unicode/XML code points;
- extremely deep recursive item definitions;
- very large rule/entry counts;
- malicious namespace and reference strings;
- unsupported raw fragments;
- atom-table safety;
- bounded error payloads.

The writer itself performs no XML parsing and must never enable external entity
resolution.

### Performance tests

Add non-flaky benchmarks outside the ordinary unit suite for:

- 100 rules;
- 1,000 rules;
- 10,000 rules;
- multiple large decision tables in one model.
- decision services with multiple output decisions;
- models with nested BKMs and invocations.

Measure output size, elapsed time, and peak memory. The initial implementation
should avoid repeated whole-document concatenation that creates quadratic
memory behavior.

## Implementation Plan

Status values:

- `not-started`
- `in-progress`
- `blocked`
- `done`

| Order | ID | Task | Status | Notes |
| ----- | -- | ---- | ------ | ----- |
| 1 | DW.1 | Define or identify the shared pinned DMN compatibility profile | done | Loader, validator, writer, schema fixtures, TCK, and docs must resolve the same version and namespace data. |
| 2 | DW.2 | Audit the loader and normalized model against the pinned DMN metamodel and XSD | done | Semantic, preservation, and rejected profiles are defined; discarded elements, attributes, and significant text normalization are covered. |
| 3 | DW.3 | Add source-profile and serialization-fidelity metadata | done | Unsupported or discarded elements, attributes, extensions, annotations, documentation, DMNDI, and merged import graphs are detected. |
| 4 | DW.4 | Correct semantic normalization needed for writing | done | FEEL text and complete import declarations are retained; deterministic semantic ordering is defined. |
| 5 | DW.5 | Add `Boxic.DMN.SerializationError` | done | Uses normalized model paths and stable error codes. |
| 6 | DW.6 | Add serialization preflight validation | done | Rejects version mismatches, invalid options/models, inconsistent identities, unsupported expressions, and lossy models. |
| 7 | DW.7 | Add the internal namespace-aware XML emitter boundary | done | Consumes the pinned profile and centralizes escaping, formatting, namespaces, XML code-point checks, and deterministic attribute ordering. |
| 8 | DW.8 | Serialize definitions, imports, item definitions, input data, decisions, and requirements | done | Covers the common container/reference model. |
| 9 | DW.9 | Serialize every normalized boxed expression | done | Includes literals, tables, contexts, functions, relations, lists, conditionals, filters, and iterators. |
| 10 | DW.10 | Serialize BKMs, invocations, bindings, and decision services | done | Covers the complete values represented by the 0.2 normalized model. |
| 11 | DW.11 | Expose `Boxic.DMN.encode_xml/2` | done | Returns XML or a non-empty list of structured errors. |
| 12 | DW.12 | Add the focused decision-table authoring API | done | Provides immutable ID-based row, column, cell, ordering, and policy operations that preserve table arity and unaffected model content. |
| 13 | DW.13 | Add unit, version-consistency, schema, round-trip, evaluation-equivalence, fidelity, authoring, and idempotence tests | done | Focused coverage includes all normalized expression families, generated tables, XSD validation, evaluation equivalence, fidelity, authoring, and byte idempotence. |
| 14 | DW.14 | Run the complete writer profile through applicable TCK fixtures | done | 69 distinct implemented-profile models audited: 0 supported, 69 rejected for the newer DMN namespace, and 0 failed. |
| 15 | DW.15 | Add property, security, and bounded performance coverage | done | Deterministic generation, injection, code-point, bounded-error, atom-safety, deep-recursion, and 100/1,000/10,000-rule benchmark coverage are implemented. |
| 16 | DW.16 | Document public guarantees, limitations, authoring operations, and examples | done | Public API docs, README, changelog, authoring examples, writer audit, and benchmark instructions are included. |

## Release Verification

The 0.2.0 release candidate passed:

- the complete umbrella test alias;
- all 1,485 selected DMN TCK cases;
- 2,042 selected FEEL TCK cases, with the expected 18 Java external-function
  cases reported as unsupported;
- the complete 69-model writer audit with zero failures;
- formatting checks and compilation with warnings as errors;
- Credo strict across the umbrella;
- Dialyzer with zero errors;
- focused DMN 1.4 XSD validation;
- local Hex package and documentation builds.

## Documentation Requirements

Add package documentation covering:

- when to use `encode_xml/2`;
- the supported DMN version and model profile;
- semantic versus textual round-trip guarantees;
- deterministic output guarantees;
- the preservation profile and the rejection behavior for unsupported
  documentation, annotations, namespace-aware extensions, and DRD/DMNDI;
- every option and default;
- structured error examples;
- a complete load-edit-write-reload example;
- decision-table authoring examples for editing cells and adding, removing, and
  reordering rows and columns.

Update the changelog with the public API, supported writer profile, and any
normalized-model additions.

## Non-goals

The initial feature does not:

- provide a visual editor;
- define application persistence or versioning;
- store files;
- fetch imports;
- resolve remote schemas;
- generate random ids;
- provide undo/redo;
- store UI draft state;
- guarantee preservation of whitespace, comments, namespace prefixes, or
  attribute ordering from the source XML;
- silently write unsupported Boxic model nodes;
- implement W3C XML canonicalization;
- serialize arbitrary maps or structs as XML.

## Acceptance Criteria

- `Boxic.DMN.encode_xml/2` is a documented public API.
- The focused decision-table authoring API is public and documented.
- Every normalized DRG element and boxed expression supported by the pinned
  loader, validator, and evaluator serializes to standard XML for the project's
  pinned DMN version.
- The writer obtains version, namespace, schema, and compatibility information
  from the same pinned profile used by the loader, validator, and test suites.
- A source-model/pinned-version mismatch returns a structured error and never
  performs an implicit upgrade or downgrade.
- Generated XML reloads and validates through the existing public API.
- Generated XML validates against the pinned official DMN schema.
- Supported fixtures retain normalized semantics after load-write-load.
- Named decisions and decision services, including multi-output services with
  BKM/invocation dependencies, return equivalent results before and after the
  round-trip.
- Repeated write-load-write operations produce identical bytes.
- Decision-table clause, rule, and entry ordering is preserved.
- Decision-table authoring operations keep rule entry counts aligned with table
  clauses and preserve unaffected model content.
- Supported preservation-profile content survives round-trips; detected
  unsupported documentation, annotations, extensions, and DMNDI cause a
  structured lossy-serialization error.
- Edited tables and models containing supported boxed expressions, BKMs,
  invocations, and decision services validate, serialize, reload, and evaluate.
- XML-special characters and Unicode are encoded safely.
- Missing, inconsistent, unresolved, unsupported, and lossy models return
  structured errors with useful model paths.
- A compatibility test proves that the loader/evaluator cannot add a normalized
  type without a corresponding writer implementation.
- Genuinely unsupported content is never silently omitted.
- The writer performs no filesystem, network, application-config, or random-id
  operations.
- The applicable TCK writer profile has a published compatibility result.
- Public documentation states the exact supported profile and round-trip
  guarantees.

## Deferred Work

The following are explicitly deferred beyond 0.2:

- a comprehensive builder for constructing definitions, imports, item
  definitions, BKMs, decision services, and every boxed expression from
  scratch;
- structured namespace-aware preservation and editing of arbitrary extension
  elements and attributes;
- a normalized DMNDI/DC/DI layout model and layout editing;
- support for a different or additional DMN specification version.

Support for another DMN version begins only when the project deliberately
changes its compatibility policy. It requires:

- a registered compatibility profile for the new version;
- an audited metamodel/schema delta;
- explicit conversion rules where normalized semantics differ;
- version-specific loader, validator, evaluator, writer, builder, schema, and
  TCK coverage;
- explicit caller selection only when more than one version is supported;
- errors for conversions that cannot preserve semantics.

It must not be implemented as arbitrary writer namespace constants or silent
output-version changes.

## References

- [OMG Decision Model and Notation](https://www.omg.org/spec/DMN)
- [Boxic DMN package](https://hex.pm/packages/boxic_dmn)
- [Boxic.DMN API](https://hexdocs.pm/boxic_dmn/Boxic.DMN.html)
- [Boxic.DMN.Model](https://hexdocs.pm/boxic_dmn/Boxic.DMN.Model.html)
- [Boxic.DMN.Model.DecisionTable](https://hexdocs.pm/boxic_dmn/Boxic.DMN.Model.DecisionTable.html)
