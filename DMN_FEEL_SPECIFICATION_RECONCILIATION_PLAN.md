# Boxic DMN and FEEL specification reconciliation plan

Status: revised proposal

Target: the next `boxic_dmn` and `boxic_feel` releases after `boxic_dmn`
0.2.0 / `boxic_feel` 0.1.0

Executable specification target: DMN 1.5, the latest formally released OMG
version, using the `20230324` MODEL and FEEL namespace family.

## Purpose

Reconcile Boxic's mature FEEL/DMN execution foundation with a strict,
evidence-backed public contract suitable for downstream consumers. The work
focuses on specification-aware validation, predictable evaluation boundaries,
structured diagnostics, safe dependency resolution, trustworthy interchange,
and accurate conformance reporting.

The immediate downstream consumer is `bpmn_engine`, whose unreleased 0.1
profile will use Boxic as its executable expression and decision
implementation. Boxic remains a standalone FEEL and DMN library.

This reconciliation does not turn Boxic into a workflow engine, a general XML
editor, or a complete modeling environment. It improves the mechanics and
behavior of the features Boxic exposes while making unsupported behavior
explicit.

## Scope principles

1. DMN 1.5 is the only executable DMN profile required by this update.
2. DMN 1.4 and earlier documents may remain inspectable where the existing
   loader can parse them safely, but backwards-compatible validation,
   evaluation, authoring, and serialization are not release requirements.
3. Beta or draft DMN versions are not executable profiles. Supporting a future
   formal release requires a separate reviewed profile update.
4. `boxic_feel` owns FEEL parsing, AST validation, value semantics, built-ins,
   unary tests, host-function integration, and evaluation.
5. `boxic_dmn` owns the normalized DMN model, DMN validation, dependency
   resolution, decision and decision-service evaluation, authoring operations,
   and XML interchange.
6. XML is the durable interchange source. Boxic never claims a normalized model
   is safely writable when content needed for the requested write was discarded
   or cannot be preserved.
7. Schema validity, normalized-model validity, executability, and writability
   are separate capabilities. A public boundary may require one or more of
   them, but conformance reporting must not collapse them into one claim.
8. The vendored native DMN 1.5 TCK revision and generated compatibility reports
   remain binding evaluation evidence. Unsupported cases stay selected and
   visible.
9. The allowlisted Elixir external-function registry is an intentional
   BEAM-native extension. It does not claim Java reflection support and must not
   make Java-specific TCK cases pass.
10. Model text can call only names supplied through trusted host configuration.
    It can never construct module names, atoms, MFA tuples, credentials, network
    clients, or other host capabilities.
11. Boxic does not acquire BPMN lifecycle, persistence, authorization,
    deployment, or UI policy.

## Findings

| ID | Finding | Required outcome |
| --- | --- | --- |
| `BX-SPEC-001` | Boxic documentation and compatibility metadata describe DMN 1.4, while the complete vendored TCK model corpus uses the DMN 1.5 `20230324` namespace. | Make DMN 1.5 the single executable profile and derive report metadata from the actual packages, source profile, schema, and TCK revision. |
| `BX-SPEC-002` | Loading records DMN 1.3, unqualified, and unknown profiles, while evaluation does not consistently require the executable profile. DMN 1.5 is currently classified only as unknown. | Recognize DMN 1.5 explicitly. Keep tolerant inspection distinct from strict DMN 1.5 validation and evaluation. Older profiles are not required to execute or serialize. |
| `BX-SPEC-003` | The loader checks XML well-formedness and normalizes selected elements but does not expose normative input validation against the DMN 1.5 XSD family. | Package and checksum the normative DMN 1.5 schema family and add a public, structured, secure XSD-validation boundary used by strict loading. |
| `BX-SPEC-004` | Expression-language handling is distributed, and an absent expression-level value is normalized immediately to `"feel"`, losing definitions-level inheritance. | Centralize declared and effective expression-language resolution for the DMN 1.5 default and exact `20230324` FEEL URI. Preserve omission in the normalized model. |
| `BX-SPEC-005` | Model validation and evaluation return heterogeneous tuples, while serialization alone has a structured error with paths and messages. | Introduce one stable diagnostic contract for schema, model, profile, import, serialization, evaluation-preflight, and evaluation errors while retaining structured FEEL causes. |
| `BX-SPEC-006` | `evaluate/4` accepts an Elixir external-function registry, but `evaluate_service/3` has no options form. The registry is currently merged into ordinary FEEL context data. | Add decision-service option parity and carry trusted host functions in a separate evaluator environment with explicit precedence and redaction rules. |
| `BX-SPEC-007` | `load_file/1` merges every sibling `.dmn` file instead of resolving only declared imports. | Add deterministic, declared-import resolution with namespace checks, cycle detection, host-supplied resolution, local-file containment, and no network access by default. |
| `BX-SPEC-008` | Documentation, DMNDI, extensions, and unmodeled attributes are detected as lossy and block writes, but the exact capability impact is not recorded. | Publish a construct capability ledger. Preserve content opaquely only where Boxic can do so safely; otherwise classify it precisely as non-writable or inspect-only. Never silently discard it during a claimed-safe write. |
| `BX-SPEC-009` | Public conformance claims do not yet separate FEEL evaluation, DMN evaluation, XML schema validity, normalized-model coverage, import behavior, and writer round-trip coverage. | Generate independent evidence and claims for every layer, with accurate versions, commits, schema checksums, and case dispositions. |
| `BX-SPEC-010` | The writer audit currently rejects the selected DMN 1.5 TCK models because they contain unmodeled content, so evaluator success does not prove native writer coverage. | Add a focused native DMN 1.5 interchange corpus for Boxic's supported public model surface, plus negative and inspect-only examples. Keep the TCK evaluator and writer evidence separate. |
| `BX-SPEC-011` | The pinned TCK revision may lag upstream changes. | Refresh through the existing delta workflow, review every added, changed, and removed case, and regenerate baselines without weakening strict CI or changing unsupported dispositions silently. |

## Public capability boundary

Parsing, validating, executing, and writing a document are different claims.
The API must make those differences visible without requiring callers to use
private modules.

Final names may follow the existing API style, but the conceptual operations
are:

```elixir
# Best-effort, non-executable inspection. No compatibility promise for old DMN.
Boxic.DMN.inspect_xml(xml)

# Strict DMN 1.5 schema and normalized-model load.
Boxic.DMN.load_xml(xml)
Boxic.DMN.load_file(path)

# Capability-specific validation of an existing or authored model.
Boxic.DMN.validate(model, for: :evaluation)
Boxic.DMN.validate(model, for: :serialization)
Boxic.DMN.validate(model, for: :authoring)

Boxic.DMN.evaluate(model, decision, context,
  external_functions: Registry
)

Boxic.DMN.evaluate_service(model, service, arguments,
  external_functions: Registry
)
```

Required semantics:

- `inspect_xml/1` may return a normalized view of a document outside DMN 1.5,
  but does not promise compatibility, execution, or serialization;
- `load_xml/1` and `load_file/1` are strict DMN 1.5 boundaries and always
  perform the required schema and model validation;
- disabling schema validation is not an option on the strict loader; callers
  wanting structural inspection use `inspect_xml/1`;
- evaluation and decision-service evaluation default to DMN 1.5 and rerun the
  relevant model/profile preflight rather than trusting a stale “previously
  validated” flag;
- authoring operations preserve or recompute capability state after every
  immutable model update;
- `encode_xml/2` emits DMN 1.5 only and never performs implicit upgrade or
  downgrade;
- serialization eligibility is checked separately from execution eligibility;
- ambiguous path-or-XML `load/1` is deprecated in favor of explicit XML and
  file APIs, with removal scheduled according to the package's 0.x policy;
- changing the existing tolerant meaning of `load_xml/1` is documented as a
  breaking 0.x API change with an explicit migration example.

## Structured diagnostics

Add a public diagnostic shared by validation, preflight, and execution:

```elixir
defmodule Boxic.DMN.Diagnostic do
  @enforce_keys [:code, :category, :path, :message]
  defstruct [
    :code,
    :category,
    :path,
    :message,
    :specification,
    :clause,
    :source_profile,
    :cause,
    :details
  ]
end
```

Categories:

- `:xml_schema`
- `:dmn_model`
- `:feel`
- `:executable_profile`
- `:import`
- `:serialization`
- `:evaluation_preflight`
- `:evaluation`

Rules:

- public operations return diagnostics in deterministic order;
- paths have a documented stable segment format and identify the XML location,
  DMN element/id, expression, rule, or clause wherever available;
- diagnostic codes have documented meanings and are treated as public API;
- `details` and the public diagnostic map representation contain only stable,
  safely serializable values;
- a DMN schema/model violation is never reported as an executable-profile
  limitation;
- an unsupported valid construct is never described as invalid DMN;
- FEEL parser and evaluator errors remain structured causes rather than being
  reduced to strings;
- public host-function failures are redacted by default; trusted logging may
  retain an explicitly configured internal cause;
- Boxic does not assign downstream publish severity or BPMN lifecycle policy;
- compatibility tuple errors may be adapted at one deprecated edge during the
  next release only; internal code and new tests use the structured type.

## Normative DMN 1.5 schema boundary

1. Add the complete normative DMN 1.5 XSD dependency family under package
   `priv/`: `DMN15.xsd`, `DMNDI15.xsd`, `DI.xsd`, and `DC.xsd`.
2. Record source URLs, checksums, specification version, and redistribution
   notices. The authoritative source is the OMG DMN 1.5 release.
3. Validate imported XML and generated XML with the same packaged schema family.
4. Use the packaged schema through a narrow runtime adapter. OTP's
   `xmerl_xsd` cannot compile the normative DMN 1.5 derivation graph, and the
   evaluated Hex alternatives either accepted invalid restrictions or bundled
   an obsolete libxml2. This release therefore uses `xmllint --nonet` and
   returns `:schema_validator_unavailable` when the executable is absent. This
   constraint is part of the published runtime contract and clean-consumer
   smoke test.
5. Disable DTDs, external entities, network access, and arbitrary local-file
   resolution.
6. Enforce documented XML size, depth, node-count, and diagnostic-count limits
   so schema validation and inspection have predictable resource behavior.
7. Return structured diagnostics rather than raw `:xmerl` records or command
   output.
8. Add positive and single-mutation negative fixtures for required attributes,
   QName/reference syntax, enum values, element order, type references,
   decision services, boxed expressions, imports, DMNDI, DTD/entity attacks,
   and resource limits.
9. Include the schema family and notices in the built Hex archive and verify
   them in the clean-consumer smoke test.

## Expression-language reconciliation

Create one resolver owned by the DMN 1.5 compatibility profile:

```elixir
Boxic.DMN.Compatibility.expression_language(
  profile,
  definitions_declaration,
  local_declaration
)
```

For strict DMN 1.5:

- the normalized model retains whether definitions-level and local declarations
  were omitted;
- a local declaration overrides the definitions declaration;
- when both are omitted, the DMN 1.5 FEEL default applies where specified;
- the exact `https://www.omg.org/spec/DMN/20230324/FEEL/` URI is executable;
- `"feel"` may remain an internal effective marker but is not emitted as a
  substitute standards URI;
- DMN 1.4, DMN 1.3, and arbitrary language URIs are not executable under the
  DMN 1.5 profile;
- a non-FEEL expression may still be inspectable or safely writable if its
  content is preserved, but Boxic does not execute it;
- loader, validator, writer, authoring API, decision evaluator,
  decision-service evaluator, and tests consume the same resolver.

Add regression coverage for definitions-level declarations, local overrides,
absent defaults, imported models, nested boxed expressions, BKMs, invocations,
decision tables, and decision services.

## Declared-import resolution

Import resolution is a library concern because it affects DMN validation and
execution, but transport and credential policy remain host concerns.

Required behavior:

1. Resolve only imports declared by the root model.
2. Validate `namespace`, `importType`, and the imported definitions namespace.
3. Reject ambiguous namespace matches, duplicate imports, cycles, missing
   imports, and profile mismatches with structured diagnostics.
4. `load_file/1` may resolve relative local files within a documented root. It
   must not scan and merge unrelated sibling files.
5. `load_xml/1` accepts no ambient filesystem or network authority. A caller
   that needs imports supplies an explicit model set or resolver.
6. A resolver returns bytes or an already inspected source; it does not receive
   evaluator context, external functions, or downstream credentials.
7. Network fetching is outside Boxic's default behavior. A host-provided
   resolver owns timeouts, authentication, caching, and network allowlisting.
8. Every imported document passes the same DMN 1.5 schema, profile,
   expression-language, and capability checks as the root document.

## Elixir external-function parity

Keep the current trust model and extend it consistently:

1. Add `Boxic.DMN.evaluate_service/4` with the same `external_functions:` option
   accepted by `evaluate/4`.
2. Extend the FEEL evaluator environment so variables, registered host
   functions, and built-ins are separate namespaces internally.
3. Define precedence explicitly: registered functions may shadow built-ins only
   when the host opts into the documented behavior; ordinary model input cannot
   shadow, enumerate, or extract the registry.
4. Thread the environment through service input decisions, output decisions,
   information requirements, BKMs, invocations, contexts, decision tables, and
   nested function calls.
5. Apply the same typed argument, return, arity, exception, timeout guidance,
   and redaction rules for direct decisions and decision services.
6. Add tests for registered functions in literal expressions, table
   input/output expressions, BKMs, invocations, and services; include unknown
   function, bad arity/type, raised exception, and unregistered MFA cases.
7. Keep the Java external-function TCK group selected and explicitly
   unsupported. Do not add Java-shaped syntax that dispatches to Elixir.

## Bounded interchange and fidelity

Boxic must be honest about the XML it accepts and writes, but this work does not
require Boxic to model every DMN element, become a general-purpose XML editor,
or provide a complete DMNDI authoring API.

Maintain a generated construct ledger with independent columns for:

- schema validity;
- normalized representation: `modeled`, `opaque`, or `not_retained`;
- evaluation impact: `supported`, `semantically_inert`, or `unsupported`;
- serialization: `modeled`, `opaque_round_trip`, or `blocked`;
- authoring safety: `safe`, `restricted`, or `blocked`;
- evidence fixture and diagnostic code.

Priorities for this release:

1. Prove deterministic DMN 1.5 writing for the existing public normalized-model
   surface.
2. Preserve standard documentation and metadata where this is straightforward
   and safe.
3. Preserve namespace/QName information required by modeled references.
4. Preserve vendor extensions or DMNDI opaquely only when namespace, ordering,
   reference integrity, and mutation behavior can be proven safe.
5. Otherwise retain enough information to issue a precise non-writable or
   inspect-only diagnostic.
6. Refuse an authoring mutation when it would invalidate anchored opaque content
   or reference integrity.
7. Define round-trip equivalence as XML Infoset plus modeled semantic
   equivalence, not byte-for-byte preservation of the original document.
8. Prove deterministic second writes and evaluation equivalence for every
   writable construct.

Opaque XML must never enable entity expansion, external resolution, FEEL
reinterpretation, Elixir execution, or hidden host authority.

## Conformance evidence

Extend the existing compatibility artifacts rather than replacing them.

The generated ledger records:

- actual Boxic package versions and source commit;
- DMN 1.5 MODEL and FEEL namespaces;
- normative schema sources and checksums;
- TCK commit and selected profile;
- source profile for every executed model;
- every TCK group/case disposition and reason;
- FEEL evaluation results;
- DMN 1.5 evaluation results;
- XSD input-validation results;
- normalized-model coverage;
- declared-import behavior;
- writer/round-trip coverage;
- explicit platform extensions;
- unsupported Java interoperability;
- inspect-only and non-writable cases.

Release claims state these independently. “All selected evaluator cases pass”
must not be presented as complete DMN interchange, complete normalized-model
coverage, or complete DMNDI support.

The TCK evaluator lane must verify that selected models are native DMN 1.5
before execution. The writer lane uses a focused native DMN 1.5 corpus designed
for Boxic's supported public model surface; TCK models with unrelated extensions
may remain expected non-writable cases.

Use the existing `update_tck.sh`, pin verification, delta report, strict
regression report, and nightly full-corpus run. A TCK refresh cannot change a
tracked baseline until every delta has a reviewed disposition.

## Phased implementation

### Phase 1 — Contract and evidence correction

- [x] Change the executable profile and public documentation to DMN 1.5.
- [x] Correct generated report versions and derive them from package metadata.
- [x] Assert that every strict TCK model uses the DMN 1.5 source profile.
- [x] Publish the capability contract, diagnostic schema, import-resolver
      contract, and API migration.
- [x] Add the construct capability ledger and record current schema/TCK
      checksums as the before-state.
- [x] Add acceptance tests or ledger assertions for `BX-SPEC-001` through
      `BX-SPEC-011`; incomplete acceptance tests remain explicitly tagged and do
      not leave ordinary CI red.

Exit: Boxic no longer labels DMN 1.5 evidence as DMN 1.4, and every later phase
has a stable public contract and measurable acceptance condition.

### Phase 2 — Secure schema and structured diagnostics

- [x] Package and checksum the normative DMN 1.5 XSD family.
- [x] Add secure runtime schema validation and resource limits.
- [x] Introduce stable diagnostics and adapt existing validation and
      serialization errors.
- [x] Add strict `load_xml/1` and `load_file/1` schema/model behavior while
      retaining explicit best-effort inspection.

Exit: malformed DMN, valid-but-unsupported DMN, unsafe XML, and profile
mismatches are distinguishable with stable paths and evidence.

### Phase 3 — DMN 1.5 execution boundary

- [x] Recognize and enforce the `20230324` MODEL profile.
- [x] Centralize declared/effective expression-language resolution.
- [x] Enforce the pinned profile before decision and service evaluation.
- [x] Replace sibling scanning with declared-import resolution.
- [x] Normalize evaluation preflight diagnostics and retain runtime tuple
      errors only at the documented 0.x compatibility edge.
- [x] Deprecate the ambiguous `load/1` compatibility API.

Exit: strict execution accepts native DMN 1.5 only, imports are explicit and
deterministic, and all evaluation paths share the same profile and language
rules.

### Phase 4 — External-function decision-service parity

- [x] Separate the trusted host-function environment from ordinary model data.
- [x] Add the options-aware decision-service API.
- [x] Thread the environment through the complete decision-service graph.
- [x] Add precedence, security, type, failure, and redaction tests.
- [x] Preserve the explicit Java-unsupported TCK disposition.

Exit: the BEAM extension behaves consistently across every FEEL/DMN invocation
surface without implying Java interoperability or exposing host configuration
as model data.

### Phase 5 — Scoped interchange fidelity

- [x] Implement the construct capability ledger in loader/model/writer behavior.
- [x] Add only the opaque preservation required for content that Boxic can
      preserve safely within its library scope.
- [x] Add the focused native DMN 1.5 round-trip corpus and independent XSD
      oracle.
- [x] Prove deterministic, Infoset, and semantic round-trip properties for the
      supported writer surface.

Exit: no claimed-writable construct is silently lost, every blocked write has a
precise diagnostic, and Boxic has not expanded into a general DMN/XML authoring
platform.

### Phase 6 — TCK refresh and release

- [x] Refresh the pinned TCK through the reviewed delta workflow.
- [x] Regenerate strict FEEL, DMN 1.5, schema, import, and writer artifacts.
- [x] Run the full corpus diagnostically and investigate every regression.
- [x] Update READMEs, changelogs, Hex contents, licenses, and release artifacts.
- [x] Build and smoke-test both Hex packages from their tarballs.

Exit: all strict profiles pass, no selected case is skipped or silently
reclassified, generated claims match tracked evidence, and a downstream
consumer can enforce DMN 1.5 without private Boxic APIs.

## Downstream handoff to `bpmn_engine`

The Boxic release is ready for adoption when `bpmn_engine` can:

1. call one strict DMN 1.5 validation/evaluation boundary;
2. use the exact `https://www.omg.org/spec/DMN/20230324/FEEL/` URI for executable
   BPMN expressions;
3. map structured Boxic diagnostics into BPMN/engine-profile lifecycle issues;
4. provide imported models or an explicit resolver without giving Boxic ambient
   network or credential authority;
5. invoke the same allowlisted Elixir registry through decisions and decision
   services;
6. remove its pre-FEEL condition evaluator and migration code;
7. remove untagged mapping-source compatibility;
8. pin exact Boxic package versions and compatibility metadata; and
9. pass direct, persisted, round-trip, and negative integration tests without
   reimplementing FEEL or DMN behavior.

## Non-goals

- Guarantee validation, evaluation, authoring, or serialization compatibility
  with DMN 1.4 or earlier in this update.
- Support a beta or draft DMN version before it becomes a formal release.
- Implement every valid DMN element or attribute merely because it exists in
  the schema.
- Become a general-purpose XML preservation, transformation, or editing library.
- Provide a complete DMNDI modeling or diagram-authoring API.
- Implement Java reflection or mark Java-specific TCK cases supported.
- Execute arbitrary Elixir source, anonymous functions, modules, or MFA tuples
  supplied by model text.
- Fetch imports from the network or manage downstream credentials by default.
- Add BPMN lifecycle, persistence, authorization, deployment, or UI policy.
- Silently upgrade older DMN documents or downgrade DMN 1.5 documents.
- Treat TCK evaluator success as proof of complete XML/DMNDI interchange.
