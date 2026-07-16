# Arbiter FEEL and DMN Engine Plan

> **Working project name:** Arbiter
>
> Arbiter is envisioned as a family of standards-oriented workflow and decision libraries. The initial focus is a standalone FEEL engine and a DMN engine, with the possibility of adding BPMN or other OMG standards in the future under the same namespace.

## 1. Objective

Build a standards-oriented DMN implementation in Elixir, structured as an umbrella project with independently publishable packages:

- a standalone FEEL engine;
- a DMN engine that depends on the FEEL engine;
- a non-published TCK integration project for compatibility testing.

The implementation should use the upstream DMN Technology Compatibility Kit directly and report compatibility against a pinned upstream revision.

`arbiter_feel` is an independent implementation. Standards behavior and progress are validated against explicit groups from the pinned official DMN TCK rather than inherited implementation history or third-party test baselines.

---

## 2. Why Elixir

Elixir is a strong fit for both FEEL and DMN because the domain maps naturally to:

- immutable evaluation contexts;
- recursive AST evaluation;
- pattern matching over expression and model node types;
- explicit result and error tuples;
- protocol- or behaviour-based type operations;
- deterministic, side-effect-free evaluation;
- concurrent and cached model execution at the service layer.

Pattern matching is particularly suitable for:

- FEEL AST nodes;
- unary tests;
- value-type dispatch;
- decision-table rules;
- hit-policy evaluation;
- DMN node execution;
- result normalization;
- structured error propagation.

OTP should be used around the evaluator, not inside each expression evaluation. Individual FEEL and DMN evaluations should normally remain pure function calls.

---

## 3. Umbrella Structure

```text
arbiter/
├── apps/
│   ├── arbiter_feel/
│   │   ├── lib/
│   │   ├── test/
│   │   └── mix.exs
│   │
│   ├── arbiter/
│   │   ├── lib/
│   │   ├── test/
│   │   └── mix.exs
│   │
│   └── arbiter_dmn_tck/
│       ├── lib/
│       ├── test/
│       └── mix.exs
│
├── vendor/
│   └── dmn-tck/
│
├── scripts/
│   ├── update_tck.sh
│   └── generate_tck_report.exs
│
├── .github/
│   └── workflows/
│
└── mix.exs
```

Dependency direction:

```text
arbiter_dmn_tck
        ↓
   arbiter_dmn
        ↓
  arbiter_feel
```

The TCK application may also invoke `arbiter_feel` directly for focused diagnostics, but formal DMN TCK compatibility should be measured through the DMN execution path.

---

## 4. Package Boundaries

## 4.1 `arbiter_feel`

The FEEL package is independently publishable and reusable outside the DMN engine.

Responsibilities:

- lexer;
- parser;
- FEEL AST;
- evaluator;
- FEEL value semantics;
- unary tests;
- built-in functions;
- name resolution;
- function invocation;
- temporal types and operations;
- ranges;
- lists and contexts;
- three-valued boolean logic;
- explicit evaluation errors.

Public API:

```elixir
Arbiter.FEEL.parse(expression)

Arbiter.FEEL.evaluate(expression, context)

Arbiter.FEEL.evaluate_ast(ast, context)
```

The public API should remain small and stable.

The FEEL package owns its parser, AST, evaluator, built-ins, and value semantics directly. External implementations may be consulted as references where licensing permits, but no external fork or source import is a project requirement or completion criterion.

---

## 4.2 `arbiter_dmn`

The DMN package depends on `arbiter_feel`.

Responsibilities:

- DMN XML parsing;
- DMN model validation;
- decision definitions;
- input data;
- literal expressions;
- decision tables;
- hit policies;
- Decision Requirement Graph execution;
- Business Knowledge Models;
- invocations;
- item definitions and type references;
- dependency resolution;
- decision-service execution;
- integration with the FEEL evaluator.

Public API:

```elixir
Arbiter.DMN.load(xml)

Arbiter.DMN.validate(model)

Arbiter.DMN.evaluate(model, decision_name, context)
```

Development dependency:

```elixir
{:arbiter_feel, "~> 0.1", path: "../arbiter_feel"}
```

The version requirement documents package compatibility, while the path dependency allows local umbrella development.

---

## 4.3 `arbiter_dmn_tck`

The TCK package is internal development infrastructure and should not be published to Hex.

Responsibilities:

- discover upstream test cases;
- parse TCK test metadata;
- load DMN models;
- execute tests against the implementation;
- normalize expected and actual values;
- compare results;
- classify outcomes;
- generate machine-readable compatibility reports;
- provide focused test selection;
- expose Mix tasks for local and CI execution.

Suggested commands:

```bash
mix tck
mix tck --all
mix tck --group 0007-date-time
mix tck --label feel
mix tck --report artifacts/tck-results.csv
mix tck --format json
```

---

## 5. FEEL Architecture

```text
FEEL source
    ↓
Lexer
    ↓
Parser
    ↓
AST
    ↓
Semantic validation
    ↓
Evaluator
    ↓
FEEL value or structured error
```

The parser must not execute expressions.

The evaluator should operate on an immutable AST and immutable context.

Evaluation contract:

```elixir
@callback evaluate(ast(), context()) ::
  {:ok, feel_value()}
  | {:error, Arbiter.FEEL.Error.t()}
```

---

## 6. FEEL Value System

The engine should define explicit FEEL semantics rather than inherit native Elixir semantics accidentally.

Suggested internal type:

```elixir
@type feel_value ::
    Decimal.t()
  | String.t()
  | boolean()
  | nil
  | Date.t()
  | Time.t()
  | DateTime.t()
  | Arbiter.FEEL.Duration.t()
  | Arbiter.FEEL.Range.t()
  | [feel_value()]
  | %{String.t() => feel_value()}
  | Arbiter.FEEL.Function.t()
```

Native Elixir values may be used internally where their semantics align with FEEL, but all operations must go through FEEL-specific modules.

Important semantic areas:

- decimal arithmetic;
- null propagation;
- three-valued logic;
- type-safe comparison;
- temporal arithmetic;
- list and context equality;
- range boundary semantics;
- function arity and overload resolution;
- distinction between `null` and evaluation failure.

---

## 7. Numeric Representation

Use `Decimal` for FEEL numbers.

Do not use native floating-point arithmetic as the semantic basis of the engine.

This affects:

- parsing;
- arithmetic;
- comparison;
- aggregation;
- division;
- rounding;
- conversion;
- serialization;
- TCK result comparison.

This decision should be made before expanding the evaluator because retrofitting decimal semantics later would affect most of the implementation.

---

## 8. DMN Architecture

```text
DMN XML
    ↓
XML parser
    ↓
Normalized DMN model
    ↓
Validation
    ↓
Dependency graph
    ↓
Decision executor
    ├── literal expression
    ├── decision table
    ├── context
    ├── invocation
    └── BKM
    ↓
FEEL evaluator
    ↓
Decision result
```

The normalized model should be independent of the XML parsing library.

Suggested model boundary:

```elixir
defmodule Arbiter.DMN.Model do
  defstruct [
    :namespace,
    :name,
    :definitions,
    :decisions,
    :input_data,
    :bkms,
    :item_definitions
  ]
end
```

The evaluator should not traverse raw XML nodes.

---

## 9. Decision Tables

Within a rule, input columns are conjunctive:

```text
column_1 AND column_2 AND column_3
```

Rows represent candidate alternatives. The hit policy determines how matching rows are resolved.

Supported hit policies:

- Unique;
- Any;
- First;
- Priority;
- Collect;
- Collect Sum;
- Collect Min;
- Collect Max;
- Collect Count;
- Output Order;
- Rule Order.

The hit-policy engine should be a separate module from rule matching.

Suggested structure:

```text
DecisionTable
├── Input evaluation
├── Unary-test matching
├── Matching-rule collection
└── Hit-policy reduction
```

---

## 10. Upstream TCK Integration

## 10.1 Principle

Use the unmodified upstream DMN TCK corpus.

Do not rewrite the upstream test suite into a custom Elixir-only suite.

The upstream repository includes Java-based reference tooling, but Arbiter does not depend on Java runners. The test corpus itself is language-neutral.

The Elixir project will implement its own vendor runner over the original upstream files.

---

## 10.2 Vendoring Strategy

Vendor a pinned snapshot of the upstream repository under `vendor/dmn-tck`.

```bash
scripts/update_tck.sh <pinned-commit>
```

The update script should:

- fetch upstream `dmn-tck/tck`;
- checkout the requested commit;
- copy repository files into `vendor/dmn-tck` without upstream `.git` metadata;
- write `vendor/dmn-tck/PINNED_COMMIT`.

CI must use the pinned revision.

CI should verify that:

- `vendor/dmn-tck/PINNED_COMMIT` exists and is non-empty;
- the pinned commit exists in the upstream repository;
- `vendor/dmn-tck` is plain vendored content (no nested git repository).

Do not automatically follow the upstream default branch during normal CI runs.

Each report should include:

```text
Engine version
FEEL package version
DMN package version
DMN TCK commit
DMN specification version
Elixir version
OTP version
Execution date
```

---

## 10.3 Test Flow

```text
Upstream DMN file
Upstream test-case XML
        ↓
TCK loader
        ↓
Normalized test case
        ↓
Arbiter.DMN.load/1
        ↓
Arbiter.DMN.evaluate/3
        ↓
Actual result normalization
        ↓
Expected result normalization
        ↓
Semantic comparison
        ↓
Compatibility result
```

The same runner should remain in place as implementation coverage expands.

Initially, many cases will be unsupported. Over time, they should move from unsupported to passing without changing the upstream corpus or the core runner architecture.

---

## 10.4 Test Outcome Model

Every discovered upstream test must receive an explicit result:

```elixir
:passed
:failed
:unsupported
:missing
:error
```

Definitions:

- `passed`: execution result matches the expected result;
- `failed`: execution completes but the semantic result is incorrect;
- `unsupported`: the model uses a deliberately unimplemented feature;
- `missing`: the runner could not locate or load required upstream artifacts;
- `error`: the engine or harness failed unexpectedly.

Unsupported cases must not be silently skipped.

A compatibility percentage should distinguish supported compatibility from total corpus coverage.

Example:

```text
Total upstream tests: 3,391
Supported tests: 1,240
Passed: 1,198
Failed: 42
Unsupported: 2,151

Compatibility on supported scope: 96.6%
Coverage of total corpus: 36.6%
```

---

## 10.5 TCK Loader

The loader should produce a stable internal test-case structure:

```elixir
defmodule Arbiter.DMN.TCK.Case do
  defstruct [
    :group,
    :id,
    :labels,
    :model_path,
    :decision_name,
    :inputs,
    :expected,
    :metadata
  ]
end
```

Responsibilities:

- discover groups;
- parse test-case XML;
- locate the corresponding DMN model;
- parse expected results;
- retain upstream identifiers and labels;
- surface malformed or missing artifacts explicitly.

---

## 10.6 Value Normalization

Value normalization should be minimal and selective.

Use native Elixir values directly when they are already sufficient and semantically compatible with FEEL.

Normalize expected or actual values only when Elixir representation is insufficient, ambiguous, or incompatible with FEEL semantics.

Do not compare serialized XML or JSON strings.

Normalization decision rule:

- no normalization: Elixir type and comparison behavior already match FEEL semantics;
- normalize one side: only one side has representation mismatch;
- normalize both sides: both values require canonicalization to compare semantically.

The comparator must support:

- decimals;
- strings;
- booleans;
- null;
- dates;
- times;
- date-times;
- durations;
- lists;
- contexts;
- nested structures;
- expected errors;
- ordered and unordered collections where required.

Typical normalization-required cases include:

- decimal lexical differences that must compare by numeric semantics;
- temporal values where timezone or duration semantics would be lost by naive comparison;
- context/list nesting where key/value representations differ but FEEL meaning is equivalent.

Decimal equality must be semantic rather than representation-based.

Temporal comparison must preserve timezone and duration semantics defined by FEEL.

---

## 10.7 No Java Runner Dependency

Compatibility execution is fully Elixir-native.

The implementation and CI pipelines must not require Java runners, Java wrapper services, or Java-side orchestration.

Avoid:

```text
Java runner
  ↓ HTTP
Elixir engine
```

Rationale:

- avoids cross-runtime protocol and serialization complexity;
- keeps deterministic behavior in a single runtime;
- reduces CI and contributor setup overhead;
- keeps debugging and profiling inside Elixir tooling.

Allowed upstream interaction:

- consume upstream DMN and test-case artifacts directly from the vendored repository;
- document any interpretation differences in Arbiter reports.

Primary and only compatibility execution path is native Elixir over the upstream corpus.

---

## 11. Verification Strategy

The unmodified official TCK corpus is the acceptance authority for standards behavior. Every FEEL or DMN feature must map to explicit upstream groups, and those groups must pass completely at the pinned commit before the feature or owning work package can be marked `done`. Local tests do not substitute for an applicable official group.

The TCK application should execute upstream cases through the dedicated runner with group-level reporting. Selected upstream cases may also be exposed through ExUnit for focused debugging, but generated per-case ExUnit tests are not required for compliance evidence.

Example:

```elixir
for test_case <- Arbiter.DMN.TCK.Loader.load_all() do
  @test_case test_case

  test "#{test_case.group}/#{test_case.id}" do
    assert :passed ==
             Arbiter.DMN.TCK.Runner.execute(@test_case)
  end
end
```

The dedicated Mix runner is the primary standards-verification path. This avoids generating thousands of local test definitions while retaining exact upstream identifiers and result classifications.

Recommended split:

- official TCK groups for standards semantics, feature acceptance, compatibility metrics, and completion gates;
- local ExUnit tests for loader/comparator/reporter integrity, dependency boundaries, public API contracts, malformed-input handling, and project-specific behavior not specified by the TCK;
- focused local regression tests only when they isolate a subtle upstream failure and materially improve diagnosis;
- optional selected-case ExUnit exposure during development, without duplicating ordinary upstream cases permanently.

Do not create local semantic tests merely to reproduce coverage already supplied by a mapped TCK group. Existing local semantic tests may remain as fast smoke tests, but their pass status is not feature-completion evidence.

---

## 12. CI Strategy

## Pull requests

Run:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix tck --suite feel --profile implemented
```

The strict implemented profile contains only wholly passing mapped groups. It should grow by complete groups as features meet their exit gates; partially passing groups remain diagnostic and do not enter the PR gate.

The core feature map should include:

- literals;
- arithmetic;
- comparisons;
- null semantics;
- basic contexts;
- basic functions;
- literal-expression DMN models.

## Nightly

Run:

```bash
mix tck --all --report artifacts/tck-results.csv
```

Nightly output should include:

- CSV report;
- JSON report;
- summary;
- failed-case list;
- unsupported-feature matrix.

## Releases

A package release should require:

- no regression in supported TCK cases;
- no unexplained reduction in supported coverage;
- a pinned TCK revision;
- a published compatibility report.

Suggested matrix:

```yaml
elixir:
  - "1.18"
  - "1.19"

otp:
  - "27"
  - "28"
```

---

## 13. Implementation Phases

## Phase 0 — Repository and Foundation Setup

- create umbrella;
- establish `arbiter_feel` as an independent implementation;
- establish package naming and module namespaces;
- add pinned vendored TCK snapshot;
- add baseline CI.

Deliverable:

- umbrella builds;
- FEEL, DMN, and TCK application boundaries compile and pass their foundation gates;
- TCK corpus is discoverable.

---

## Phase 1 — TCK Harness Foundation

- implement upstream test discovery;
- parse test-case metadata;
- load DMN model files;
- create canonical value normalization;
- create report generation;
- classify unsupported cases explicitly;
- run a minimal literal-expression test end to end.

Deliverable:

- native Elixir runner executes at least one upstream case;
- full corpus can be enumerated and classified.

---

## Phase 2 — FEEL Core Compliance

Implement and validate:

- literals;
- decimal numbers;
- arithmetic;
- comparisons;
- boolean expressions;
- null semantics;
- names and contexts;
- basic lists;
- `if then else`.

Deliverable:

- FEEL core profile with published pass/fail results.

---

## Phase 3 — FEEL Structural Features

Implement and validate:

- ranges;
- unary tests;
- path expressions;
- bracket filters;
- `for` expressions;
- `some` and `every`;
- user-defined functions;
- closures;
- context scoping and shadowing.

Deliverable:

- expanded FEEL compatibility matrix.

---

## Phase 4 — Built-in Functions and Temporal Semantics

Implement and validate:

- string functions;
- list functions;
- numeric functions;
- aggregation;
- conversion;
- dates;
- times;
- date-times;
- durations;
- temporal arithmetic;
- timezone behaviour.

Deliverable:

- broad FEEL TCK coverage with remaining gaps documented by feature.

---

## Phase 5 — Minimal DMN Execution

Implement:

- DMN definitions parsing;
- input data;
- decisions;
- literal expressions;
- dependency resolution;
- decision invocation by name.

Deliverable:

- FEEL is exercised through the formal DMN execution path;
- relevant upstream cases no longer require direct FEEL extraction.

---

## Phase 6 — Decision Tables

Implement:

- input clauses;
- output clauses;
- rules;
- unary-test matching;
- multi-column conjunction;
- multiple outputs;
- default outputs;
- validation.

Deliverable:

- decision-table TCK groups execute.

---

## Phase 7 — Hit Policies

Implement and validate:

- Unique;
- Any;
- First;
- Priority;
- Collect;
- Collect Sum;
- Collect Min;
- Collect Max;
- Collect Count;
- Output Order;
- Rule Order.

Deliverable:

- hit-policy TCK groups execute and report compatibility independently.

---

## Phase 8 — Full DMN Graph Features

Implement:

- Decision Requirement Graphs;
- required decisions;
- required input data;
- Business Knowledge Models;
- invocations;
- contexts;
- item definitions;
- decision services.

Deliverable:

- substantial DMN TCK coverage beyond FEEL and decision tables.

---

## Phase 9 — Compliance Phase

Close the gap between the passing implemented profiles and the complete pinned
TCK corpus. This phase owns every official group not enabled by Phases 0–8.

Implement and verify:

- remaining FEEL numeric, aggregate, string, type, context, and temporal semantics;
- portability decisions for platform-specific external functions;
- remaining DMN core-expression, decision-table, graph, import, and boxed-expression behavior;
- explicit execution status for all 3,545 pinned result entries;
- profile expansion only when an assigned group passes completely.

Deliverable:

- all 150 official groups have one explicit work-package owner and disposition;
- every implemented group passes completely and is published;
- remaining `unsupported` results are deliberate, documented portability decisions rather than disabled or silently skipped cases.

---

## 14. Versioning and Publication

Publish `arbiter_feel` and `arbiter_dmn` independently.

Example:

```text
arbiter_feel 0.1.x
arbiter_dmn  0.1.x
```

`arbiter_dmn` should declare an explicit compatible FEEL version range.

The TCK package remains private to the repository.

Release notes should include:

- new supported FEEL or DMN features;
- TCK revision;
- supported test count;
- pass count;
- known unsupported groups;
- semantic breaking changes.

---

## 15. Public Module Names

Suggested namespaces:

```elixir
Arbiter.FEEL
Arbiter.FEEL.Parser
Arbiter.FEEL.Evaluator
Arbiter.FEEL.Builtins

Arbiter.DMN
Arbiter.DMN.Model
Arbiter.DMN.Parser
Arbiter.DMN.DecisionTable
Arbiter.DMN.HitPolicy
Arbiter.DMN.Executor

Arbiter.DMN.TCK
Arbiter.DMN.TCK.Loader
Arbiter.DMN.TCK.Runner
Arbiter.DMN.TCK.Comparator
Arbiter.DMN.TCK.Reporter
```

Package names may differ from application names if required by Hex availability, but module names should remain stable.

---

## 16. Design Principles

1. FEEL and DMN remain separate publishable packages.
2. DMN depends on FEEL, never the reverse.
3. TCK code remains outside the production API.
4. The upstream TCK corpus remains unmodified.
5. Every upstream test receives an explicit status.
6. Compatibility and corpus coverage are reported separately.
7. FEEL semantics are explicit and must not rely accidentally on Elixir semantics.
8. Decimal arithmetic is foundational.
9. Evaluation remains deterministic and side-effect free.
10. OTP is used for model lifecycle and service concerns, not for ordinary expression evaluation.
11. XML parsing is separated from the normalized DMN model.
12. Unsupported features are visible, measurable, and progressively eliminated.
13. Official mapped TCK groups, not local semantic tests, determine standards-feature completion.
14. Local tests protect infrastructure and internal contracts without duplicating ordinary upstream cases.

---

## 17. Initial Milestone

The first meaningful milestone is:

> Load a pinned upstream TCK case, parse its DMN model and test metadata, execute a literal expression through `arbiter_dmn` and `arbiter_feel`, compare the canonical result, and emit a TCK-compatible report entry.

This proves the complete architecture before investing heavily in language implementation.

---

## 18. Plan Evaluation

Current plan strengths:

- clear package boundaries and dependency direction;
- explicit architecture for FEEL and DMN execution paths;
- strong TCK integration principles;
- phased implementation roadmap with sensible sequencing.

Traceability gaps addressed in this section:

- requirements are not uniquely identified;
- phase deliverables are not decomposed into auditable work packages;
- acceptance criteria are described but not consistently measurable;
- dependency gates are implicit rather than explicit;
- progress reporting is not normalized across phases.

The sections below convert the roadmap into a traceable implementation plan.

---

## 19. Traceable Requirement Catalog

Each requirement must be testable and map to one or more implementation work packages.

| Requirement ID | Requirement                                                                                                  | Verification                                             |
| -------------- | ------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------- |
| RQ-ARCH-001    | Project is an umbrella with `arbiter_feel`, `arbiter_dmn`, and `arbiter_dmn_tck` apps.                       | `mix compile`; app discovery in umbrella; CI build job.  |
| RQ-ARCH-002    | Dependency direction is `arbiter_dmn -> arbiter_feel`; TCK is non-production.                                | Compile-time deps and boundary checks in tests.          |
| RQ-FEEL-001    | FEEL parser returns AST without evaluation side effects.                                                     | Parser unit tests and purity checks.                     |
| RQ-FEEL-002    | FEEL evaluation returns `{:ok, value}` or structured `{:error, error}` tuples.                               | Evaluator contract tests.                                |
| RQ-FEEL-003    | FEEL numbers use `Decimal` semantics end-to-end.                                                             | Mapped numeric TCK groups.                               |
| RQ-FEEL-004    | FEEL null semantics and three-valued logic are implemented.                                                  | FEEL logic TCK groups.                                   |
| RQ-FEEL-005    | FEEL unary tests, ranges, contexts, and lists are supported per scope.                                       | Structural FEEL TCK groups.                              |
| RQ-FEEL-006    | FEEL temporal semantics (date/time/date-time/duration) are explicit and deterministic.                       | Mapped temporal TCK groups.                              |
| RQ-DMN-001     | DMN XML is parsed into a normalized internal model.                                                          | Parser and model validation tests.                       |
| RQ-DMN-002     | DMN evaluator executes literal expressions through FEEL integration.                                         | End-to-end DMN literal-expression TCK groups.            |
| RQ-DMN-003     | Decision tables execute with rule matching and separate hit-policy reduction.                                | Mapped decision-table TCK groups.                        |
| RQ-DMN-004     | Supported hit policies produce deterministic, spec-aligned outputs.                                          | Hit-policy targeted TCK groups.                          |
| RQ-DMN-005     | DRG features (BKMs, invocations, dependencies, decision services) execute correctly.                         | Mapped full-graph DMN groups.                            |
| RQ-TCK-001     | Upstream TCK corpus is vendored unmodified at a pinned commit.                                               | Vendored pin integrity checks in CI.                     |
| RQ-TCK-002     | Every discovered test case receives explicit status (`passed`, `failed`, `unsupported`, `missing`, `error`). | Runner classification tests and report validation.       |
| RQ-TCK-003     | Comparator normalizes expected/actual values semantically (not string form).                                 | Comparator tests across value types.                     |
| RQ-TCK-004     | Compatibility reports include mandatory metadata and machine-readable outputs.                               | CSV/JSON schema checks in CI.                            |
| RQ-TCK-005     | Compatibility execution and CI do not require Java runners or Java orchestration.                            | CI job definitions and execution-path integration tests. |
| RQ-CI-001      | PR and nightly pipelines enforce quality gates and publish artifacts.                                        | CI workflow runs and artifact retention checks.          |
| RQ-REL-001     | Releases document compatibility deltas and pinned TCK revision.                                              | Release checklist verification.                          |
| RQ-COMP-001    | Every pinned official group has exactly one feature owner and explicit implementation disposition.          | Compliance inventory reconciliation.                    |
| RQ-COMP-002    | Disabled corpus entries are reduced through completely passing, published feature groups.                    | Per-work-package strict TCK gates.                       |

---

## 20. Work Package Breakdown

Each work package is independently reviewable and tied to explicit outputs.

| Work Package | Scope                                          | Depends On   | Primary Outputs                                         | Exit Criteria                                           |
| ------------ | ---------------------------------------------- | ------------ | ------------------------------------------------------- | ------------------------------------------------------- |
| WP-00        | Umbrella/bootstrap and repository conventions. | None         | umbrella structure, baseline CI, naming conventions     | `mix test` passes in umbrella; CI green.                |
| WP-01        | Vendor and pin upstream DMN TCK.               | WP-00        | `vendor/dmn-tck` snapshot, pin file, update script      | Pinned commit enforced in CI.                           |
| WP-02        | TCK discovery and case loading.                | WP-01        | `Loader`, internal case struct, malformed-case handling | Full corpus enumerates with no silent skips.            |
| WP-03        | Result model and reporting pipeline.           | WP-02        | status model, CSV/JSON reporter, summary output         | Reports generated with required metadata fields.        |
| WP-04        | FEEL parser contract hardening.                | WP-00        | parser API, AST validation layer                        | Parser tests pass; no evaluation in parse stage.        |
| WP-05        | FEEL evaluator core semantics.                 | WP-04        | arithmetic, comparisons, logic, null semantics          | Every applicable WP-05 exit-matrix group passes completely at the pinned commit and is published in the core profile. |
| WP-06        | FEEL structural expressions.                   | WP-05        | unary tests, ranges, list/context semantics             | Every applicable WP-06 exit-matrix group passes completely at the pinned commit and is published in the structural profile. |
| WP-07        | FEEL built-ins and temporal semantics.         | WP-06        | built-ins and temporal modules                          | Every applicable WP-07 exit-matrix group passes completely at the pinned commit and is published in built-in/temporal profiles. |
| WP-08        | DMN normalized model and validator.            | WP-00        | DMN parser, model structs, validation                   | Literal model loads into normalized structures.         |
| WP-09        | DMN literal-expression execution path.         | WP-08, WP-05 | executor wiring to FEEL                                 | Every mapped minimal-DMN/literal-expression group passes completely and is published. |
| WP-10        | Decision table engine.                         | WP-09, WP-06 | input evaluation, rule matching, outputs                | Every mapped decision-table group passes completely and is published. |
| WP-11        | Hit policy module.                             | WP-10        | all target hit policy reducers                          | Every mapped group for each target hit policy passes; per-policy compatibility is published independently. |
| WP-12        | Full DMN graph features.                       | WP-11, WP-07 | DRG execution, BKMs, invocations, services              | Every mapped advanced-DMN group passes completely and coverage is published. |
| WP-13        | CI maturity and release gates.                 | WP-03, WP-12 | PR/nightly workflows, release checklist                 | No regression gate and reporting gate enforced.         |
| WP-14        | FEEL numeric completion.                       | WP-07        | advanced numeric functions and edge values              | All 15 mapped groups pass 209/209 and are published.     |
| WP-15        | FEEL aggregate statistics.                    | WP-07        | boolean aggregates and statistical functions            | All 5 mapped groups pass 75/75 and are published.        |
| WP-16        | FEEL strings, Unicode, and regular expressions.| WP-07        | remaining string and regex functions                    | All 8 mapped groups pass 169/169 and are published.      |
| WP-17        | FEEL types, coercion, predicates, and contexts.| WP-06, WP-07 | type tests, coercion, metadata and context functions     | All 10 mapped groups pass 354/354 and are published.     |
| WP-18        | FEEL calendar and interval completion.         | WP-07        | at-literals, calendar functions, intervals, clock values| All 9 mapped groups pass 135/135 and are published.      |
| WP-19        | FEEL external-function portability.            | WP-07        | platform interop policy and external-function contract  | `0076` has an implemented portable path or an explicit documented unsupported disposition for all 18 entries. |
| WP-20        | DMN core expressions and collections.          | WP-09, WP-16 | remaining literal models, collections and arithmetic    | All 21 mapped groups pass 1,213/1,213 and are published. |
| WP-21        | DMN decision-table completion.                 | WP-10, WP-11 | remaining policies, tables, variable inputs and examples| All 9 mapped groups pass 60/60 and are published.        |
| WP-22        | DMN functions, scopes, and recursion.          | WP-12        | invocations, user functions, scopes, nesting, recursion | All 8 mapped groups pass 31/31 and are published.        |
| WP-23        | DMN imports and reference semantics.           | WP-12        | imports, local references and no-logic models            | All 4 mapped groups pass 5/5 and are published.          |
| WP-24        | Boxed expressions and remaining collections.   | WP-12, WP-20 | boxed control forms, list replacement and range function| All 8 mapped groups pass 99/99 and are published.        |

---

## 21. Requirement-to-Work Mapping (Trace Matrix)

| Requirement ID | Implemented By | Validated By                       |
| -------------- | -------------- | ---------------------------------- |
| RQ-ARCH-001    | WP-00          | Umbrella compile/test CI job       |
| RQ-ARCH-002    | WP-00          | Dependency boundary tests          |
| RQ-FEEL-001    | WP-04          | Parser unit tests                  |
| RQ-FEEL-002    | WP-05          | Evaluator contract tests           |
| RQ-FEEL-003    | WP-05          | FEEL numeric TCK profile           |
| RQ-FEEL-004    | WP-05          | FEEL logic/null TCK profile        |
| RQ-FEEL-005    | WP-06          | FEEL structural TCK profile        |
| RQ-FEEL-006    | WP-07          | FEEL temporal TCK profile          |
| RQ-DMN-001     | WP-08          | DMN parser/validator tests         |
| RQ-DMN-002     | WP-09          | DMN literal-expression TCK profile |
| RQ-DMN-003     | WP-10          | Decision-table TCK profile         |
| RQ-DMN-004     | WP-11          | Hit-policy per-group TCK profile   |
| RQ-DMN-005     | WP-12          | Full DMN advanced profile          |
| RQ-TCK-001     | WP-01          | CI vendored pin integrity check    |
| RQ-TCK-002     | WP-02, WP-03   | Runner classification tests        |
| RQ-TCK-003     | WP-03          | Comparator semantic equality tests |
| RQ-TCK-004     | WP-03          | Report schema and metadata checks  |
| RQ-TCK-005     | WP-03, WP-13   | CI and execution-path verification |
| RQ-CI-001      | WP-13          | PR/nightly workflow verification   |
| RQ-REL-001     | WP-13          | Release checklist sign-off         |
| RQ-COMP-001    | WP-14–WP-24    | Reconciled compliance inventory    |
| RQ-COMP-002    | WP-14–WP-24    | Expanded strict profiles/reports   |

No requirement should exist without both a work package and a validation path.

---

## 22. Milestone Gates

Each milestone is complete only when all included requirements are verified.

| Milestone              | Included Work Packages | Gate Criteria                                                                        |
| ---------------------- | ---------------------- | ------------------------------------------------------------------------------------ |
| M0 Foundation          | WP-00, WP-01           | Umbrella green, TCK pinned and discoverable.                                         |
| M1 Harness             | WP-02, WP-03           | Corpus fully enumerated; all tests classified; reports emitted.                      |
| M2 FEEL Core           | WP-04, WP-05           | Core FEEL profile stable with published pass/fail counts.                            |
| M3 FEEL Advanced       | WP-06, WP-07           | Structural and temporal profiles executable and tracked.                             |
| M4 DMN Minimal         | WP-08, WP-09           | DMN literal-expression flow passes end-to-end against upstream case(s).              |
| M5 Tables and Policies | WP-10, WP-11           | Decision-table and hit-policy groups execute with independent compatibility metrics. |
| M6 Advanced DMN        | WP-12                  | DRG and advanced features reported with compatibility deltas.                        |
| M7 Release Readiness   | WP-13                  | Regression gates active; release checklist complete; compatibility report published. |
| M8 Compliance          | WP-14–WP-24            | All remaining groups have a verified passing result or explicit portability disposition; no entry is disabled without an owner. |

---

## 23. Progress Tracking

This is the single authoritative progress section for the project. Phase descriptions, work-package definitions, requirement mappings, and milestone gates above define scope and acceptance criteria; they do not independently record completion. Update progress only in this section.

### 23.1 Status model

Use these states for phases, work packages, and tasks:

- `not_started`: no implementation work has begun;
- `in_progress`: implementation exists or active work remains, but the exit criteria are not satisfied;
- `blocked`: progress cannot continue until an identified dependency or decision is resolved;
- `in_review`: implementation and verification are complete and awaiting acceptance;
- `done`: all exit criteria are verified with current evidence.

Roll-up rules:

- a work package is `done` only when every required task is `done` and its exit criteria are verified;
- a phase is `done` only when every work package and deliverable associated with that phase is `done`;
- every standards feature must have an explicit official test-group mapping before it can be marked `done`;
- every applicable mapped group must pass completely at the pinned commit before its standards feature can be marked `done`;
- local unit, smoke, and regression tests demonstrate implementation behavior but never count as standards compatibility or feature-completion evidence when an applicable official group exists;
- local tests are required only where they protect harness infrastructure, architecture boundaries, internal/public contracts, malformed-input behavior, focused diagnostics, or project-specific behavior absent from the TCK;
- a passing test count used as completion evidence must identify the corpus, profile, pinned commit, and report artifact; diagnostic counts must identify the pinned commit and must not be presented as completion;
- missing or silently skipped upstream cases prevent the TCK loader and harness work packages from being marked `done`.

Minimum evidence required for `done`:

- implementation is present and appropriate infrastructure/contract tests pass;
- umbrella format, compile, and test gates pass;
- applicable official TCK groups are mapped, pass completely, and are recorded in a pinned profile/report;
- no unresolved acceptance-criteria gap remains;
- requirement, work-package, and milestone mappings remain accurate.

### 23.2 Current phase roll-up

Status date: **2026-07-16**

| Phase                                               | Status        | Current assessment                                                                                                                                                                                                                                 | Completion condition                                                                                                 |
| --------------------------------------------------- | ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Phase 0 — Repository and Foundation Setup           | `done`        | The umbrella, independent `arbiter_feel` implementation boundary, namespaces, dependency-direction checks, baseline CI, reproducible TCK update scripts, and verified official corpus at `0dbcaf9b98bc3af4e36d44a7aed95e9e85703a13` are present. | None for the current Phase 0 scope. |
| Phase 1 — TCK Harness Foundation                    | `done`        | All 3,545 pinned result entries are discovered and explicitly classifiable; expected errors and canonical nested values are normalized; semantic comparison, safe CLI selection, and versioned CSV/JSON reporting are verified. The pinned strict report is published under `compatibility/feel-implemented-0dbcaf9b.{csv,json}`. | None for the current Phase 1 scope. |
| Phase 2 — FEEL Core Compliance                      | `done`        | The 162 core cases remain included in the passing strict profile across conditionals, constants, arithmetic, contexts, lists, scalar equality, and boolean/null logic. Cross-type range/unary-test and temporal equality cases from `0068` are explicitly assigned to later work. | None for the current Phase 2 scope. |
| Phase 3 — FEEL Structural Features                  | `done`        | Paths, filters, projections, function invocation, `in`/unary tests, alternative ranges, numeric sequences, multi-binding iteration, partial results, quantifiers, closures, and scoping are implemented. Official `0001-filter`, `0090-feel-paths`, and `1131-feel-function-invocation` pass 13/13 and are enabled; cross-temporal and DMN-dependent cases are explicitly reassigned. | None for the current Phase 3 scope. |
| Phase 4 — Built-in Functions and Temporal Semantics | `done` | Lossless FEEL temporal and duration-kind types preserve precision and identity; `tzdata` supplies complete IANA-zone resolution and DST-aware date-time arithmetic. Every wholly WP-07-owned mapped group passes. After WP-12 and WP-14–WP-16 expansions, the strict FEEL profile now passes 1,553/1,553. | None for the defined Phase 4 scope; remaining compliance groups are owned by Phase 9. |
| Phase 5 — Minimal DMN Execution                     | `done` | Namespace-qualified DMN models normalize and validate through WP-08. WP-09 recursively resolves required input data and literal decisions, injects their declared FEEL names, detects cycles, and executes by decision ID or name. Official `0084-feel-for-loops` passes 24/24 through the formal path. | None for the current minimal literal-expression scope. |
| Phase 6 — Decision Tables                           | `done` | Normalized input/output clauses and rules, table validation, multi-column unary-test conjunction, UNIQUE matching, single/multiple outputs, and defaults are implemented. Official `0004-simpletable-U` and `0010-multi-output-U` pass 6/6 in the first strict DMN profile. | None for the WP-10 table-engine scope; additional hit policies belong to WP-11. |
| Phase 7 — Hit Policies                              | `done` | FIRST, ANY, PRIORITY, RULE ORDER, OUTPUT ORDER, and COLLECT reducers are implemented, including unaggregated collection and COUNT/SUM/MIN/MAX aggregation. Twelve official policy groups pass 36/36; together with WP-10 the strict DMN profile passes 42/42. | None for the targeted hit-policy scope. |
| Phase 8 — Full DMN Graph Features                   | `done` | DRG dependencies, boxed contexts and relations, item definitions, BKMs, invocations, boxed functions, and decision services are normalized, validated, and executable. The strict profiles publish all applicable mapped groups at 100%: 71 newly enabled FEEL-suite entries and 35 newly enabled DMN-suite entries. | None for the current Phase 8 scope. |
| Phase 9 — Compliance Phase                          | `in_progress` | The phase began from 1,177 published entries across 52 groups. WP-14–WP-16 are complete, bringing the strict profiles to 1,630/3,545 entries across 80 groups (45.98% total-corpus coverage); 70 groups and 1,915 entries remain assigned to WP-17–WP-24. | Complete the remaining eight compliance work packages; publish every passing group and explicitly disposition platform-specific cases. |

### 23.3 Work-package roll-up

| Work package | Status        | Completed foundation                                                                                                      | Remaining exit work                                                                                                                                                    |
| ------------ | ------------- | ------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| WP-00        | `done`        | Umbrella structure, executable dependency-boundary regression tests, documented internal-only TCK packaging, baseline CI, and passing local gates. | None for the current WP-00 scope. |
| WP-01        | `done`        | The narrow official TestCases corpus, pin, upstream URL, tree identity, checksum manifest, reproducible updater, and byte-for-byte upstream CI verification are present. | None for the current WP-01 scope. |
| WP-02        | `done`        | All numbered official test documents are discovered; namespaced XML, model layout, scalar/list/component values, identifiers, labels, and compliance levels are normalized; empty/malformed documents and missing models are explicit; the pin-specific integrity baseline is tested. | None for the current WP-02 scope. |
| WP-03        | `done`        | Five explicit statuses; exact typed-string loading; expected-error handling; Decimal, temporal, duration, nested, ordered, and unordered comparison; separate compatibility/coverage metrics; safe CLI selection; and versioned typed CSV/JSON schemas are tested. Strict reports are tracked at `compatibility/{feel,dmn}-implemented-0dbcaf9b.{csv,json}`. | None for the current WP-03 scope. |
| WP-04        | `done`        | Public parse/evaluate APIs, a recursive AST validation boundary, structured syntax/AST errors, and parser/validator regression tests exist. | None for the current WP-04 scope. |
| WP-05        | `done`        | Conditionals, constants, arithmetic, contexts, lists, scalar equality, and boolean/null logic pass `0032`, `0057`, `0064`, `0065`, `0066`, `0069`, `0100`, `0101`, `0102`, `0105`, `0106`, and `0107` (162/162). The pinned core report is published. | None for the current WP-05 scope; cross-type `0068` cases are tracked by WP-06/WP-07. |
| WP-06        | `done`        | Structural semantics are implemented; official filter, path, and direct function-invocation groups pass 13/13. Structural portions of `0068`, `0072`, and `0084` now pass, while their remaining cases require WP-07 temporal values or WP-09/WP-12 DMN dependencies. | None for the current WP-06 scope; reassigned cross-feature cases remain visible in the exit matrix. |
| WP-07        | `done` | Numeric/string groups pass 116/116; temporal constructors pass 273/273; equality passes 114/114; membership passes 327/327; all are enabled. Complete IANA resolution, DST-aware date-time duration arithmetic, general string conversion, and core list operations are implemented. Properties now pass 53/53 with WP-12 boxed contexts, and iteration passes 24/24 with WP-09. | None for the defined WP-07 scope; remaining temporal/calendar semantics are assigned to WP-18. |
| WP-08        | `done`        | Namespace-independent parsing produces explicit definitions, input-data, variable, decision, information-requirement, and literal-expression structs. Validation reports missing/duplicate identifiers and names, unresolved references, missing variables/text, unsupported expression kinds/languages, and malformed documents. A pinned official literal model loads and validates. | None for WP-08; dependency execution belongs to WP-09. |
| WP-09        | `done`        | Recursive input/decision requirement resolution, declared-name context injection, dependency memoization, cycle detection, and execution by ID/name are implemented. Official `0084-feel-for-loops` passes 24/24 and is enabled in the pinned strict profile. | None for the minimal literal-expression execution scope. |
| WP-10        | `done`        | Decision tables normalize into explicit clauses/rules; validation covers missing components, entry cardinality, expressions, and unsupported policies. UNIQUE tables evaluate inputs once, conjunctively match unary tests, reject multiple hits, and return scalar, context, default, or null outputs. Official single/multi-output groups pass 6/6. | None for WP-10; non-UNIQUE reducers remain WP-11 work. |
| WP-11        | `done`        | Hit policies are normalized and validated independently. Deterministic reducers cover FIRST, ANY consistency, priority ordering, rule/output ordering, collection, and numeric/count aggregations. All twelve mapped official groups pass 3/3 and are enabled. | None for WP-11. |
| WP-12        | `done` | Normalized models and recursive execution cover contexts, relations, item definitions, BKMs, invocations, function values, and decision services. Official `0016`, `0033`, `0037`, `0038`, `0074`, `0085`, and `0092` pass 106/106 and are published across the strict profiles. | None for the advanced-DMN scope. |
| WP-13        | `done` | PR/push CI verifies the pin, format, warning-free compilation, tests, both strict profiles, and regression thresholds. A scheduled/manual nightly workflow runs the full corpus and retains complete and strict CSV/JSON artifacts. `RELEASE_CHECKLIST.md` and the compatibility-delta script define release evidence. | None for the current CI and release-gate scope. |
| WP-14        | `done` | Advanced numeric operations, named arguments, left-associative exponentiation, product forms, modulo sign semantics, decimal scaling, special values, and all four rounding modes are implemented. All 15 mapped groups pass 209/209 and are published. | None. |
| WP-15        | `done` | Three-valued all/any aggregation, Decimal median/mode, sample standard deviation, scalar/vararg/list forms, named arguments, and invalid-input behavior are implemented. All 5 mapped groups pass 75/75 and are published. | None. |
| WP-16        | `done` | Unicode escape decoding and identifiers, canonical string conversion, splitting/joining, substring search, XML Schema regex matching/replacement, flags, and invalid-input behavior are implemented. All 8 mapped groups pass 169/169 and are published. | None. |
| WP-17        | `not_started` | Inventory assigns 10 FEEL type/coercion/predicate/context groups (354 entries). | Complete type tests, coercion, comments, metadata, predicates, and context operations; pass and publish 354/354. |
| WP-18        | `not_started` | Inventory assigns 9 FEEL calendar/interval groups (135 entries). | Complete at-literals, calendar extraction, year-month durations, interval relations, `now`, and `today`; pass and publish 135/135. |
| WP-19        | `not_started` | Inventory isolates the platform-specific external-Java group (18 entries). | Establish the Elixir portability disposition and ensure all 18 entries are explicitly reported rather than disabled. |
| WP-20        | `not_started` | Inventory assigns 21 DMN core-expression/collection groups (1,213 entries). | Complete literal-model arithmetic and collection behavior; pass and publish 1,213/1,213. |
| WP-21        | `not_started` | Inventory assigns 9 remaining decision-table groups (60 entries). | Complete ANY/PRIORITY table variants, variable inputs, list semantics, and end-to-end examples; pass and publish 60/60. |
| WP-22        | `not_started` | Inventory assigns 8 DMN function/scope/recursion groups (31 entries). | Complete invocation, user-function, nested-scope, DRG-scope, and recursion semantics; pass and publish 31/31. |
| WP-23        | `not_started` | Inventory assigns 4 DMN import/reference groups (5 entries). | Complete imports, nested imports, local hrefs, and no-decision-logic handling; pass and publish 5/5. |
| WP-24        | `not_started` | Inventory assigns 8 boxed-expression/collection groups (99 entries). | Complete boxed conditional/filter/for/quantifier/list forms plus list replacement and range construction; pass and publish 99/99. |

### 23.4 Detailed active task register

Task IDs are stable references for commits, reports, and weekly updates. A task remains `in_progress` until its stated acceptance evidence exists.

| Task    | Work package | Status        | Task and acceptance evidence                                                                                                               |
| ------- | ------------ | ------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| TCK-01  | WP-01        | `done`        | Official TestCases corpus vendored at `0dbcaf9b98bc3af4e36d44a7aed95e9e85703a13`; source URL recorded, ancillary upstream content excluded, and fabricated fixtures removed. |
| TCK-02  | WP-01        | `done`        | Verification fetches the exact SHA, checks the upstream TestCases tree, validates every local checksum, and compares the corpus byte-for-byte with upstream. |
| TCK-03  | WP-02        | `done`        | Namespace-aware official XML/model discovery and scalar, list, and nested-component normalization are covered by tests.                   |
| TCK-04  | WP-02        | `done`        | Every `*-test-*.xml` document is discovered; empty/malformed XML or metadata becomes an explicit error case; missing models receive `missing`; regression tests prevent silent omission. |
| TCK-05  | WP-02        | `done`        | Pin-specific baseline verifies 150 official test documents, 154 DMN models, 3,545 normalized result entries, zero load errors, and zero missing referenced models. |
| TCK-06  | WP-03        | `done`        | Comparator tests cover Decimal normalization, dates/times/date-times, durations, nested maps/lists, and ordered/unordered duplicate-preserving list semantics; 1,412 expected-error entries are normalized and runner-tested. |
| TCK-07  | WP-03        | `done`        | Summary and report schemas expose supported compatibility, selected-suite coverage, and total-corpus coverage separately. |
| TCK-08  | WP-03        | `done`        | `--all`, `--profile`, `--group`, `--label`, `--report`, and `--format csv|json|both` behavior is documented; unsafe, missing, and unsupported combinations are rejected by tests. |
| TCK-09  | WP-03        | `done`        | Versioned CSV/JSON schema tests cover required runtime/pin metadata, summary metrics, case identity, expected/actual/error values, and typed machine-readable serialization without `inspect/1`. |
| FEEL-01 | WP-05        | `done`        | Lazy `if then else` parsing/evaluation covers true, false, null, and non-boolean conditions; official `0032-conditionals` passes 6/6 and is enabled in the strict profile. |
| FEEL-02 | WP-05        | `done`        | Pinned core profile and tracked CSV/JSON report pass 162/162 across `0032`, `0057`, `0064`, `0065`, `0066`, `0069`, `0100`, `0101`, `0102`, `0105`, `0106`, and `0107`; cross-type `0068` cases are deferred explicitly to WP-06/WP-07. |
| FEEL-03 | WP-06        | `done`        | Official `0001-filter` (1/1), `0090-feel-paths` (4/4), and `1131-feel-function-invocation` (8/8) pass completely and are enabled in the strict profile. |
| FEEL-04 | WP-06        | `done`        | Structural gaps were resolved: `0072-feel-in` improved from 3/327 to 279/327 with only temporal cases remaining; `0084-feel-for-loops` improved from 12/24 to 21/24 with two temporal and one DMN-dependency case remaining; all structural range/unary-test cases in `0068` pass. |
| FEEL-05 | WP-07        | `done`        | Mapped numeric/string functions pass 116/116, including `1110-feel-contains-function` 10/10; general `string` conversion and core list built-ins are covered by focused contract tests. |
| FEEL-06 | WP-07        | `done`        | `sum`, `min`, and `max` preserve Decimal values and compare directly with `Decimal.compare/2`, without float conversion. |
| FEEL-07 | WP-07        | `done`        | Signed and fractional ISO durations, duration `abs`, named construction, normalization, and numeric comparison pass `1120-feel-duration-function` 50/50. |
| FEEL-08 | WP-07        | `done`        | Lossless time/date-time construction, offset/named-zone identity, nanoseconds, comparison, membership, properties, and temporal arithmetic are implemented; `tzdata` supplies complete IANA resolution and DST transitions. |
| FEEL-09 | WP-07        | `done`        | All wholly WP-07-owned mapped groups pass and are enabled; after WP-12 and WP-14–WP-16 additions the refreshed pinned report publishes 1,553/1,553 passing cases with zero failures, unsupported, missing, or errors. |
| DMN-01  | WP-08        | `done`        | Namespace-qualified and unqualified DMN definitions parse into normalized structs independent of prefixes and raw `:xmerl` records; the pinned `0100-feel-constants` model loads and validates. |
| DMN-02  | WP-08        | `done`        | Definitions, input data, decisions, variables, information requirements, and literal expressions have explicit normalized structures and ID-keyed indexes. |
| DMN-03  | WP-08        | `done`        | Focused validator tests cover required metadata, duplicate IDs/names, missing input variables and expression text, unresolved references, unsupported expression kinds/languages, malformed XML, and invalid roots. |
| DMN-04  | WP-09        | `done`        | Required input and decision references resolve recursively by ID, bind declared DMN/FEEL names into immutable contexts, memoize results, report missing inputs/references, and reject cycles. |
| DMN-05  | WP-09        | `done`        | Official `0084-feel-for-loops` passes 24/24 end to end, including `decision_014` consuming the `days in weekend` decision; the group remains enabled in the current 1,553-case pinned FEEL profile. |
| DMN-06  | WP-10        | `done`        | `0004-simpletable-U` and `0010-multi-output-U` pass 3/3 each through normalized tables, multi-column unary tests, scalar/multiple outputs, and the UNIQUE reducer; the 6/6 DMN profile is published. |
| DMN-07  | WP-11        | `done`        | Twelve official groups covering FIRST, RULE ORDER, OUTPUT ORDER, MIN/SUM/COUNT COLLECT, ANY, PRIORITY, and multi-output COLLECT pass 36/36. MAX is covered by a focused contract test because the pinned corpus has no MAX counterpart. |
| DMN-08  | WP-12        | `done`        | Boxed contexts, relation expressions, recursive graph dependencies, and item-definition-backed values pass `0074-feel-properties` 53/53, `0016-some-every` 8/8, and `0033-for-loops` 4/4. |
| DMN-09  | WP-12        | `done`        | BKM definitions, implicit/explicit invocation parameters, first-class built-ins/lambdas/BKMs, and decision-service invocation pass `0037` 2/2, `0038` 2/2, `0092-feel-lambda` 18/18, and `0085-decision-services` 19/19. |
| CI-01   | WP-13        | `done`        | Fabricated fixture profiles and reports were removed; CI verifies the official pinned corpus, and the root test alias runs only the targeted official FEEL implemented profile. |
| CI-02   | WP-13        | `done` | `.github/workflows/tck-nightly.yml` runs the complete pinned corpus daily and on manual dispatch, writes full and strict CSV/JSON reports, and retains them for 30 days even when a gate fails. |
| CI-03   | WP-13        | `done` | `scripts/check_tck_regression.exs` rejects a changed pin, reduced pass count, supported compatibility, or suite coverage, and any strict-profile failed/error/missing/unsupported entry. PR/push CI and nightly apply it to both suites. |
| CI-04   | WP-13        | `done` | `RELEASE_CHECKLIST.md` requires pinned reports, compatibility deltas, known gaps, dependency ranges, and breaking-change disclosure; `scripts/tck_compatibility_delta.exs` produces the release-note metric table. |
| COMP-01 | WP-14–WP-24  | `done` | Reconciled all 150 groups and 3,545 entries against the implemented profiles: 52 groups/1,177 entries published, 98 groups/2,368 entries assigned exactly once below, with no unassigned group. |
| COMP-02 | WP-14–WP-19  | `in_progress` | WP-14–WP-16 contribute 453/453 newly published FEEL entries; complete WP-17–WP-19 and continue expanding the FEEL strict profile group-by-group. |
| COMP-03 | WP-20–WP-24  | `not_started` | Complete the remaining DMN/boxed compliance inventory and expand the DMN strict profile group-by-group. |
| COMP-04 | WP-14        | `done` | All 15 numeric-completion groups pass 209/209 and remain enabled in the strict FEEL profile. |

### 23.5 Official TCK feature exit matrix

An applicable feature is complete only when every group assigned to it passes in full at the pinned commit and is included in a published profile/report. Partial pass counts are diagnostic evidence, not completion. Groups marked `candidate` must be reviewed for exact semantic scope before they can be removed or reassigned.

| Owner | Feature gate | Official groups | Current evidence | Exit condition |
| ----- | ------------ | --------------- | ---------------- | -------------- |
| WP-05 | Conditionals | `0032-conditionals` | `6/6`; enabled | Group remains fully passing. |
| WP-05 | Constants and literals | `0100-feel-constants`, `0101-feel-constants`, `0102-feel-constants` | `2/2`, `6/6`, `4/4`; all enabled | All three groups remain fully passing. |
| WP-05 | Boolean and null logic | `0064-feel-conjunction`, `0065-feel-disjunction`, `0066-feel-negation`, `0106-feel-ternary-logic`, `0107-feel-ternary-logic-not` | `19/19`, `19/19`, `6/6`, `18/18`, `3/3`; all enabled | All five groups remain fully passing. |
| WP-05 | Numeric arithmetic and scalar comparison semantics | `0105-feel-math` | `33/33`; enabled. Scalar equality behavior is exercised by the passing core profile. | Group remains fully passing. |
| WP-05 | Core contexts and lists | `0057-feel-context`, `0069-feel-list` | `11/11`, `35/35`; both enabled | Both groups remain fully passing. |
| WP-07 | Cross-type equality | `0068-feel-equality` | `114/114`; enabled | Group remains fully passing. |
| WP-06 | Filter, paths, and direct invocation | `0001-filter`, `0090-feel-paths`, `1131-feel-function-invocation` | `1/1`, `4/4`, `8/8`; all enabled | All three groups remain fully passing. |
| WP-07/WP-09 | Cross-feature iteration | `0084-feel-for-loops` | `24/24`; enabled. The required `days in weekend` decision is evaluated and injected through WP-09. | Group remains fully passing. |
| WP-07 | Cross-type ranges and membership | `0072-feel-in` | `327/327`; enabled | Group remains fully passing. |
| WP-07/WP-12 | Temporal and range properties | `0074-feel-properties` | `53/53`; enabled in the FEEL profile. Boxed DMN contexts supply the final ten results. | Group remains fully passing. |
| WP-09/WP-12 | DMN-dependent structural expressions | `0016-some-every`, `0033-for-loops`, `0092-feel-lambda` | `8/8`, `4/4`, and `18/18`; all enabled in the appropriate strict profile. | All three groups remain fully passing. |
| WP-12 | BKMs and decision services | `0037-dt-on-bkm-implicit-params`, `0038-dt-on-bkm-explicit-params`, `0085-decision-services` | `2/2`, `2/2`, and `19/19`; all enabled in the DMN profile. | All three groups remain fully passing. |
| WP-18 | Allen-style interval relation built-ins | `1130-feel-interval` | Scope review found that boxed contexts now execute, but the group exercises the FEEL `before`, `after`, `meets`, `overlaps`, and related interval functions rather than WP-12 graph behavior. It remains outside the profile pending WP-18. | Implement the complete interval-relation family and enable the group only at 14/14. |
| WP-07 | Numeric built-ins | `0050-feel-abs-function`, `0058-feel-number-function`, `0105-feel-math`, `1101-feel-floor-function`, `1102-feel-ceiling-function` | `17/17`, `21/21`, `33/33`, `17/17`, `17/17`; all enabled | All five groups remain fully passing. |
| WP-14 | Numeric completion | `0051-feel-sqrt-function`, `0052-feel-exp-function`, `0053-feel-log-function`, `0054-feel-even-function`, `0055-feel-odd-function`, `0056-feel-modulo-function`, `0075-feel-exponent`, `0077-feel-nan`, `0078-feel-infinity`, `0094-feel-product-function`, `1100-feel-decimal-function`, `1141-feel-round-up-function`, `1142-feel-round-down-function`, `1143-feel-round-half-up-function`, `1144-feel-round-half-down-function` | `209/209`; all enabled in the FEEL profile. | All fifteen groups remain fully passing. |
| WP-15 | Aggregate statistics | `0059-feel-all-function`, `0060-feel-any-function`, `0061-feel-median-function`, `0062-feel-mode-function`, `0063-feel-stddev-function` | `75/75`; all enabled in the FEEL profile. | All five groups remain fully passing. |
| WP-16 | Strings, Unicode, and regular expressions | `0067-feel-split-function`, `0079-feel-string-function`, `0083-feel-unicode`, `1107-feel-substring-before-function`, `1108-feel-substring-after-function`, `1109-feel-replace-function`, `1111-feel-matches-function`, `1140-feel-string-join-function` | `169/169`; all enabled in the FEEL profile. | All eight groups remain fully passing. |
| WP-07 | String built-ins | `1103-feel-substring-function`, `1104-feel-string-length-function`, `1105-feel-upper-case-function`, `1106-feel-lower-case-function`, `1110-feel-contains-function` | `11/11`, `6/6`, `8/8`, `9/9`, `10/10`; all enabled | All five groups remain fully passing. |
| WP-07 | Temporal constructors | `1115-feel-date-function`, `1116-feel-time-function`, `1117-feel-date-and-time-function`, `1120-feel-duration-function` | `52/52`, `83/83`, `88/88`, `50/50`; all enabled | All four groups remain fully passing. |
| WP-10 | UNIQUE decision tables | `0004-simpletable-U`, `0010-multi-output-U` | `3/3`, `3/3`; both enabled in the DMN implemented profile | Both groups remain fully passing; other hit policies are mapped to WP-11. |
| WP-11 | FIRST | `0108-first-hitpolicy`, `0111-first-hitpolicy-singleoutputcol` | `3/3`, `3/3`; enabled | Both groups remain fully passing. |
| WP-11 | RULE ORDER | `0109-ruleOrder-hitpolicy`, `0112-ruleOrder-hitpolicy-singleinoutcol` | `3/3`, `3/3`; enabled | Both groups remain fully passing. |
| WP-11 | OUTPUT ORDER | `0110-outputOrder-hitpolicy`, `0113-outputOrder-hitpolicy-singleinoutcol` | `3/3`, `3/3`; enabled | Both groups remain fully passing. |
| WP-11 | COLLECT aggregations | `0114-min-collect-hitpolicy`, `0115-sum-collect-hitpolicy`, `0116-count-collect-hitpolicy`, `0119-multi-collect-hitpolicy` | `3/3` each; enabled. MAX has focused local coverage. | All four groups remain fully passing and MAX contract coverage remains green. |
| WP-11 | ANY and PRIORITY | `0117-multi-any-hitpolicy`, `0118-multi-priority-hitpolicy` | `3/3`, `3/3`; enabled | Both groups remain fully passing. |

Counts above are result-entry counts from the vendored TestCases corpus at `0dbcaf9b98bc3af4e36d44a7aed95e9e85703a13`, measured on 2026-07-15. Failed and errored entries remain visible in diagnostic runs; only wholly passing groups enter the strict implemented profile.

### 23.6 Compliance inventory

This phase-baseline inventory is derived from the pinned loader output, not directory estimates. At Phase 9 entry, the eleven work packages contained all 98 groups and all 2,368 entries then outside the implemented profiles. WP-14–WP-16 have since promoted 28 groups/453 entries, leaving 70 groups/1,915 entries. Group counts in parentheses are result-entry counts. A group may enter a strict profile only when every assigned entry passes.

| Work package | Logical feature set | Assigned official groups | Total |
| ------------ | ------------------- | ------------------------ | ----: |
| WP-14 | FEEL advanced numeric functions and edge values | `0051-feel-sqrt-function` (15), `0052-feel-exp-function` (15), `0053-feel-log-function` (15), `0054-feel-even-function` (17), `0055-feel-odd-function` (17), `0056-feel-modulo-function` (28), `0075-feel-exponent` (12), `0077-feel-nan` (1), `0078-feel-infinity` (2), `0094-feel-product-function` (13), `1100-feel-decimal-function` (10), `1141-feel-round-up-function` (16), `1142-feel-round-down-function` (16), `1143-feel-round-half-up-function` (16), `1144-feel-round-half-down-function` (16) | 15 groups / 209 entries |
| WP-15 | FEEL boolean aggregates and statistics | `0059-feel-all-function` (19), `0060-feel-any-function` (17), `0061-feel-median-function` (14), `0062-feel-mode-function` (13), `0063-feel-stddev-function` (12) | 5 groups / 75 entries |
| WP-16 | FEEL strings, Unicode, and regular expressions | `0067-feel-split-function` (9), `0079-feel-string-function` (37), `0083-feel-unicode` (14), `1107-feel-substring-before-function` (9), `1108-feel-substring-after-function` (10), `1109-feel-replace-function` (28), `1111-feel-matches-function` (40), `1140-feel-string-join-function` (22) | 8 groups / 169 entries |
| WP-17 | FEEL types, coercion, predicates, metadata, and contexts | `0070-feel-instance-of` (142), `0071-feel-between` (38), `0073-feel-comments` (3), `0080-feel-getvalue-function` (14), `0081-feel-getentries-function` (9), `0082-feel-coercion` (36), `0103-feel-is-function` (50), `1145-feel-context-function` (18), `1146-feel-context-put-function` (30), `1147-feel-context-merge-function` (14) | 10 groups / 354 entries |
| WP-18 | FEEL calendar, duration, interval, and clock semantics | `0093-feel-at-literals` (19), `0095-feel-day-of-year-function` (19), `0096-feel-day-of-week-function` (12), `0097-feel-month-of-year-function` (12), `0098-feel-week-of-year-function` (19), `1121-feel-years-and-months-duration-function` (36), `1130-feel-interval` (14), `1148-feel-now-function` (2), `1149-feel-today-function` (2) | 9 groups / 135 entries |
| WP-19 | Platform-specific external functions | `0076-feel-external-java` (18) | 1 group / 18 entries |
| WP-20 | DMN core expressions, input data, arithmetic, and collections | `0001-input-data-string` (1), `0002-input-data-number` (1), `0002-string-functions` (4), `0003-input-data-string-allowed-values` (1), `0003-iteration` (1), `0006-join` (1), `0007-date-time` (19), `0008-LX-arithmetic` (3), `0008-listGen` (10), `0009-append-flatten` (10), `0010-concatenate` (6), `0011-insert-remove` (6), `0012-list-functions` (19), `0013-sort` (3), `0014-loan-comparison` (2), `0015-all-any` (10), `0020-vacation-days` (7), `0021-singleton-list` (5), `0035-test-structure-output` (3), `0099-arithmetic-negation` (14), `0100-arithmetic` (1,087) | 21 groups / 1,213 entries |
| WP-21 | Remaining decision tables and end-to-end examples | `0004-lending` (11), `0005-simpletable-A` (3), `0006-simpletable-P1` (3), `0007-simpletable-P2` (3), `0017-tableTests` (4), `0019-flight-rebooking` (1), `0036-dt-variable-input` (24), `0039-dt-list-semantics` (2), `0087-chapter-11-example` (9) | 9 groups / 60 entries |
| WP-22 | DMN functions, invocation, scopes, nesting, and recursion | `0005-literal-invocation` (3), `0009-invocation-arithmetic` (3), `0030-user-defined-functions` (2), `0031-user-defined-functions` (3), `0034-drg-scopes` (12), `0040-singlenestedcontext` (3), `0041-multiple-nestedcontext` (3), `0088-recursion` (2) | 8 groups / 31 entries |
| WP-23 | DMN imports, references, and no-logic models | `0086-import` (2), `0088-no-decision-logic` (1), `0089-nested-inputdata-imports` (1), `0091-local-hrefs` (1) | 4 groups / 5 entries |
| WP-24 | Boxed expressions and remaining collection functions | `1150-boxed-conditional` (3), `1151-boxed-filter` (4), `1152-boxed-for` (2), `1153-boxed-some` (5), `1154-boxed-every` (5), `1155-list-replace-function` (22), `1156-range-function` (56), `1161-boxed-list-expression` (2) | 8 groups / 99 entries |
| **Total** | **Complete remaining inventory** | **Every group outside the implemented profiles, assigned once** | **98 groups / 2,368 entries** |

`0076-feel-external-java` is isolated because an Elixir engine cannot honestly claim Java interoperation by accident. WP-19 must decide and document whether Arbiter supplies an equivalent external-function adapter or reports these cases as an intentional platform limitation. That decision affects full-corpus coverage but must not weaken supported-scope compatibility.

### 23.7 Next execution sequence

Work should proceed in this order because the upstream corpus is the evidence base for all FEEL and DMN completion claims:

1. begin WP-14 numeric completion, which includes several already partially implemented functions and provides fast profile growth;
2. complete the remaining FEEL packages WP-15–WP-18, while resolving WP-19 independently as a portability decision;
3. execute WP-20 before WP-21–WP-24 because its core-expression and collection semantics are dependencies for most remaining DMN groups;
4. use the completed CI and release gates to protect every group added to either strict profile.

### 23.8 Progress update record

Each progress update should change this section in one commit and include:

- reporting date and pinned TCK commit;
- task status changes with evidence links or artifact paths;
- newly passed, failed, unsupported, missing, and error counts by profile;
- supported compatibility and total-corpus coverage;
- blockers, risks, and the next task IDs to execute.

Do not add separate current-status tables elsewhere in the plan. Historical results belong in dated report artifacts or release notes rather than accumulating in this document.
