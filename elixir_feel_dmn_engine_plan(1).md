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

The initial implementation will start from a fork of RodarFeel and progressively improve it until the relevant FEEL behaviour is compatible with the TCK.

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

The initial codebase may be based on a fork of RodarFeel, but the fork should remain focused on FEEL only.

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

## Phase 0 — Repository and Fork Setup

- create umbrella;
- fork RodarFeel;
- import the fork into `arbiter_feel`;
- establish package naming and module namespaces;
- add pinned vendored TCK snapshot;
- add baseline CI;
- record current RodarFeel behaviour.

Deliverable:

- umbrella builds;
- existing RodarFeel tests pass;
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

Status date: **2026-07-15**

| Phase                                               | Status        | Current assessment                                                                                                                                                                                                                                 | Completion condition                                                                                                 |
| --------------------------------------------------- | ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Phase 0 — Repository and Fork Setup                 | `in_progress` | Umbrella, namespaces, baseline CI, narrow reproducible update scripts, and the verified official upstream corpus at `0dbcaf9b98bc3af4e36d44a7aed95e9e85703a13` are present. RodarFeel baseline/fork evidence is not recorded. | Record the FEEL baseline and satisfy the remaining Phase 0 deliverable. |
| Phase 1 — TCK Harness Foundation                    | `in_progress` | The loader discovers and normalizes the official namespaced corpus into 3,545 result entries; malformed metadata and missing models receive explicit statuses; the runner, comparator, reporter, and Mix task exist. | Complete the remaining comparison/reporting work in WP-03 and publish compatibility/coverage reports. |
| Phase 2 — FEEL Core Compliance                      | `in_progress` | The pinned strict profile passes 71/71 cases across constants and boolean/null logic groups. Arithmetic, equality, contexts, and lists remain only partially compatible; `if then else` is not implemented. | Make every WP-05 exit-matrix group pass, implement remaining core syntax, and publish the pinned core profile artifact. |
| Phase 3 — FEEL Structural Features                  | `in_progress` | Ranges, unary tests, paths, filters, projections, quantifiers, closures, and scoping have unit tests. Upstream structural compatibility has not been established. | Execute the relevant pinned upstream groups and document remaining semantic gaps. |
| Phase 4 — Built-in Functions and Temporal Semantics | `in_progress` | Initial string/list/numeric built-ins and date/time/duration operations exist. The fabricated `4/4` profile and its reports were removed; built-in and temporal semantics remain incomplete. | Complete the scoped built-ins and temporal semantics and publish feature-level upstream results and known gaps. |
| Phase 5 — Minimal DMN Execution                     | `in_progress` | Simple literal-expression models load and evaluate by decision name through FEEL. Input-data modeling, dependencies, normalized definitions, and meaningful validation remain incomplete.                                                          | Pass relevant pinned upstream literal-expression cases through the formal DMN execution path.                        |
| Phase 6 — Decision Tables                           | `not_started` | No decision-table parser or executor exists.                                                                                                                                                                                                       | Complete WP-10 and execute decision-table groups.                                                                    |
| Phase 7 — Hit Policies                              | `not_started` | No hit-policy reducers exist.                                                                                                                                                                                                                      | Complete WP-11 with per-policy compatibility reports.                                                                |
| Phase 8 — Full DMN Graph Features                   | `not_started` | DRG, BKM, invocation, item-definition, and decision-service execution are not implemented.                                                                                                                                                         | Complete WP-12 and report advanced DMN coverage.                                                                     |

### 23.3 Work-package roll-up

| Work package | Status        | Completed foundation                                                                                                      | Remaining exit work                                                                                                                                                    |
| ------------ | ------------- | ------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| WP-00        | `done`        | Umbrella structure, executable dependency-boundary regression tests, documented internal-only TCK packaging, baseline CI, and passing local gates. | None for the current WP-00 scope. |
| WP-01        | `done`        | The narrow official TestCases corpus, pin, upstream URL, tree identity, checksum manifest, reproducible updater, and byte-for-byte upstream CI verification are present. | None for the current WP-01 scope. |
| WP-02        | `done`        | All numbered official test documents are discovered; namespaced XML, model layout, scalar/list/component values, identifiers, labels, and compliance levels are normalized; empty/malformed documents and missing models are explicit; the pin-specific integrity baseline is tested. | None for the current WP-02 scope. |
| WP-03        | `in_progress` | Five result statuses and CSV/JSON output with JSON metadata exist.                                                        | Complete normalization, expected-error and collection comparison, compatibility/coverage metrics, report schema tests, and functional CLI format options.              |
| WP-04        | `done`        | Public parse/evaluate APIs, a recursive AST validation boundary, structured syntax/AST errors, and parser/validator regression tests exist. | None for the current WP-04 scope. |
| WP-05        | `in_progress` | Constants and boolean/null logic pass official groups `0100`, `0102`, `0064`, `0065`, `0066`, `0106`, and `0107` (71/71 cases). | Add `if then else`; make the WP-05 exit-matrix groups for constants, math, equality, contexts, and lists pass completely; publish the pinned core report. |
| WP-06        | `in_progress` | Structural expressions and focused unit/regression tests exist.                                                           | Validate official upstream structural groups and correct any discovered semantics or scoping gaps.                                                                     |
| WP-07        | `in_progress` | Initial built-ins, temporal value construction, duration representation, and temporal arithmetic exist.                   | Expand FEEL built-ins, remove float-based Decimal ordering, complete duration/timezone semantics, and validate upstream temporal groups.                               |
| WP-08        | `in_progress` | A normalized model skeleton and literal-expression XML extraction exist.                                                  | Add namespace-aware DMN parsing, structured definitions/input data/decisions, and substantive validation.                                                              |
| WP-09        | `in_progress` | A local literal-expression case executes through DMN and FEEL.                                                            | Add dependency resolution and prove the path against pinned upstream cases.                                                                                            |
| WP-10        | `not_started` | No implementation yet.                                                                                                    | Implement decision-table parsing, validation, matching, outputs, and tests.                                                                                            |
| WP-11        | `not_started` | No implementation yet.                                                                                                    | Implement separate hit-policy reducers and per-policy tests/reports.                                                                                                   |
| WP-12        | `not_started` | No implementation yet.                                                                                                    | Implement DRG dependencies, BKMs, invocations, item definitions, and decision services.                                                                                |
| WP-13        | `in_progress` | PR/push CI runs format, compile, tests, pin verification, and official-corpus loader regression tests.                    | Add nightly/full-corpus jobs, artifact retention, compatibility regression gates, and release checklist/reporting.                                                     |

### 23.4 Detailed active task register

Task IDs are stable references for commits, reports, and weekly updates. A task remains `in_progress` until its stated acceptance evidence exists.

| Task    | Work package | Status        | Task and acceptance evidence                                                                                                               |
| ------- | ------------ | ------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| TCK-01  | WP-01        | `done`        | Official TestCases corpus vendored at `0dbcaf9b98bc3af4e36d44a7aed95e9e85703a13`; source URL recorded, ancillary upstream content excluded, and fabricated fixtures removed. |
| TCK-02  | WP-01        | `done`        | Verification fetches the exact SHA, checks the upstream TestCases tree, validates every local checksum, and compares the corpus byte-for-byte with upstream. |
| TCK-03  | WP-02        | `done`        | Namespace-aware official XML/model discovery and scalar, list, and nested-component normalization are covered by tests.                   |
| TCK-04  | WP-02        | `done`        | Every `*-test-*.xml` document is discovered; empty/malformed XML or metadata becomes an explicit error case; missing models receive `missing`; regression tests prevent silent omission. |
| TCK-05  | WP-02        | `done`        | Pin-specific baseline verifies 150 official test documents, 154 DMN models, 3,545 normalized result entries, zero load errors, and zero missing referenced models. |
| TCK-06  | WP-03        | `in_progress` | Extend semantic comparison for durations, expected errors, nested values, and ordered/unordered collections where required.                |
| TCK-07  | WP-03        | `in_progress` | Report supported compatibility and total-corpus coverage separately.                                                                       |
| TCK-08  | WP-03        | `in_progress` | Make `--all`, `--profile`, and `--format` behavior explicit and tested; reject unsupported CLI combinations.                               |
| TCK-09  | WP-03        | `not_started` | Add report schema tests covering mandatory metadata and machine-readable values without relying on `inspect/1` serialization.              |
| FEEL-01 | WP-05        | `in_progress` | Implement parser/evaluator support for `if then else` with null and type-error tests.                                                      |
| FEEL-02 | WP-05        | `in_progress` | Strict pinned baseline passes 71/71 across `0064`, `0065`, `0066`, `0100`, `0102`, `0106`, and `0107`; complete every WP-05 exit-matrix group and publish the core report. |
| FEEL-03 | WP-06        | `in_progress` | Use the WP-06 exit matrix as the structural completion gate; every mapped group must pass completely and appear in the published profile. |
| FEEL-04 | WP-06        | `in_progress` | Resolve structural semantic gaps discovered by upstream range, unary-test, path/filter, quantifier, and function cases.                    |
| FEEL-05 | WP-07        | `in_progress` | Expand the built-in registry and implement missing/advertised functions, including the currently registered `string` conversion.           |
| FEEL-06 | WP-07        | `in_progress` | Preserve Decimal semantics in aggregation and ordering without float conversion.                                                           |
| FEEL-07 | WP-07        | `in_progress` | Complete signed/fractional duration parsing and required year-month/day-time distinctions.                                                 |
| FEEL-08 | WP-07        | `in_progress` | Complete FEEL timezone-aware time/date-time construction, comparison, and arithmetic semantics.                                            |
| FEEL-09 | WP-07        | `in_progress` | Complete every applicable WP-07 exit-matrix group and publish built-in and temporal profiles with feature-level known gaps. |
| DMN-01  | WP-08        | `in_progress` | Implement namespace-aware DMN definitions parsing into normalized structs independent of raw XML.                                          |
| DMN-02  | WP-08        | `in_progress` | Model input data, decisions, information requirements, and literal expressions explicitly.                                                 |
| DMN-03  | WP-08        | `in_progress` | Add validation for identifiers, references, unsupported expression kinds, and malformed definitions.                                       |
| DMN-04  | WP-09        | `in_progress` | Implement dependency resolution and inject required input/decision results into FEEL contexts.                                             |
| DMN-05  | WP-09        | `in_progress` | Pass and report pinned upstream minimal-DMN/literal-expression cases end to end.                                                           |
| CI-01   | WP-13        | `done`        | Fabricated fixture profiles and reports were removed; CI verifies the official pinned corpus, and the root test alias runs only the targeted official FEEL implemented profile. |
| CI-02   | WP-13        | `not_started` | Add scheduled full-corpus execution with retained CSV/JSON artifacts.                                                                      |
| CI-03   | WP-13        | `not_started` | Add supported-scope compatibility and total-coverage regression thresholds.                                                                |
| CI-04   | WP-13        | `not_started` | Add release checklist and compatibility-delta report requirements.                                                                         |

### 23.5 Official TCK feature exit matrix

An applicable feature is complete only when every group assigned to it passes in full at the pinned commit and is included in a published profile/report. Partial pass counts are diagnostic evidence, not completion. Groups marked `candidate` must be reviewed for exact semantic scope before they can be removed or reassigned.

| Owner | Feature gate | Official groups | Current evidence | Exit condition |
| ----- | ------------ | --------------- | ---------------- | -------------- |
| WP-05 | Constants and literals | `0100-feel-constants`, `0101-feel-constants`, `0102-feel-constants` | `2/2`, `4/6`, `4/4`; `0100` and `0102` enabled | All three groups pass and are enabled. |
| WP-05 | Boolean and null logic | `0064-feel-conjunction`, `0065-feel-disjunction`, `0066-feel-negation`, `0106-feel-ternary-logic`, `0107-feel-ternary-logic-not` | `19/19`, `19/19`, `6/6`, `18/18`, `3/3`; all enabled | All five groups remain fully passing. |
| WP-05 | Numeric and comparison semantics | `0068-feel-equality`, `0105-feel-math` | `59/114`, `25/33` | Both groups pass and are enabled. |
| WP-05 | Core contexts and lists | `0057-feel-context`, `0069-feel-list` | `8/11`, `13/35` | Both groups pass and are enabled. |
| WP-06 | Paths and properties | `0074-feel-properties`, `0090-feel-paths` | `8/53`, `2/4` | Both groups pass and are enabled. |
| WP-06 | Iteration and functions | `0084-feel-for-loops`, `0092-feel-lambda`, `1131-feel-function-invocation` | `3/24`, `0/18`, `0/8` | All three groups pass and are enabled. |
| WP-06 | Ranges and membership | `0072-feel-in`, `1130-feel-interval` | `candidate`; `1130` currently `0/14` | Confirm scope, then make applicable groups pass and enable them. |
| WP-07 | Numeric built-ins | `0050-feel-abs-function`, `0058-feel-number-function`, `0105-feel-math`, `1101-feel-floor-function`, `1102-feel-ceiling-function` | `3/17`, `0/21`, `25/33`, `3/17`, `3/17` | Applicable groups pass and are enabled; shared `0105` gate is satisfied with WP-05. |
| WP-07 | String built-ins | `1103-feel-substring-function`, `1104-feel-string-length-function`, `1105-feel-upper-case-function`, `1106-feel-lower-case-function` | `7/11`, `0/6`, `0/8`, `0/9` | All four groups pass and are enabled. |
| WP-07 | Temporal constructors | `1115-feel-date-function`, `1116-feel-time-function`, `1117-feel-date-and-time-function`, `1120-feel-duration-function` | `4/52`, `10/83`, `1/88`, `25/50` | All four groups pass and are enabled. |

Counts above are result-entry counts from the vendored TestCases corpus at `0dbcaf9b98bc3af4e36d44a7aed95e9e85703a13`, measured on 2026-07-15. Failed and errored entries remain visible in diagnostic runs; only wholly passing groups enter the strict implemented profile.

### 23.6 Next execution sequence

Work should proceed in this order because the upstream corpus is the evidence base for all FEEL and DMN completion claims:

1. complete TCK-06 through TCK-09 so failures and unsupported behavior are measured accurately;
2. complete FEEL-01 and publish the real core baseline in FEEL-02;
3. use that baseline to drive FEEL-03 through FEEL-09 rather than expanding local fixtures as compatibility evidence;
4. complete DMN-01 through DMN-05 and verify literal-expression execution against upstream cases;
5. begin WP-10 only after the minimal DMN model and upstream execution path are stable;
6. mature CI through CI-02 to CI-04 as upstream profiles become reliable.

### 23.7 Progress update record

Each progress update should change this section in one commit and include:

- reporting date and pinned TCK commit;
- task status changes with evidence links or artifact paths;
- newly passed, failed, unsupported, missing, and error counts by profile;
- supported compatibility and total-corpus coverage;
- blockers, risks, and the next task IDs to execute.

Do not add separate current-status tables elsewhere in the plan. Historical results belong in dated report artifacts or release notes rather than accumulating in this document.
