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

## 11. ExUnit Integration

The TCK application should dynamically expose upstream cases as ExUnit tests or execute them through a dedicated runner with equivalent reporting.

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

For large suites, a custom Mix task may be preferable to generating thousands of normal ExUnit tests. ExUnit should still be used for focused debugging and regression tests.

Recommended split:

- normal ExUnit tests for local unit and regression coverage;
- TCK Mix runner for full corpus execution;
- generated ExUnit tests for selected groups during development.

---

## 12. CI Strategy

## Pull requests

Run:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix tck --profile core
```

The core profile should include:

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
| RQ-FEEL-003    | FEEL numbers use `Decimal` semantics end-to-end.                                                             | Numeric TCK groups and unit tests.                       |
| RQ-FEEL-004    | FEEL null semantics and three-valued logic are implemented.                                                  | FEEL logic TCK groups.                                   |
| RQ-FEEL-005    | FEEL unary tests, ranges, contexts, and lists are supported per scope.                                       | Structural FEEL TCK groups.                              |
| RQ-FEEL-006    | FEEL temporal semantics (date/time/date-time/duration) are explicit and deterministic.                       | Temporal TCK groups and regression tests.                |
| RQ-DMN-001     | DMN XML is parsed into a normalized internal model.                                                          | Parser and model validation tests.                       |
| RQ-DMN-002     | DMN evaluator executes literal expressions through FEEL integration.                                         | End-to-end DMN literal-expression TCK groups.            |
| RQ-DMN-003     | Decision tables execute with rule matching and separate hit-policy reduction.                                | Decision-table unit tests and TCK groups.                |
| RQ-DMN-004     | Supported hit policies produce deterministic, spec-aligned outputs.                                          | Hit-policy targeted TCK groups.                          |
| RQ-DMN-005     | DRG features (BKMs, invocations, dependencies, decision services) execute correctly.                         | Full-graph DMN groups and regression suite.              |
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
| WP-05        | FEEL evaluator core semantics.                 | WP-04        | arithmetic, comparisons, logic, null semantics          | Core FEEL profile measurable via TCK subset.            |
| WP-06        | FEEL structural expressions.                   | WP-05        | unary tests, ranges, list/context semantics             | Structural FEEL groups executed with pass/fail metrics. |
| WP-07        | FEEL built-ins and temporal semantics.         | WP-06        | built-ins and temporal modules                          | Temporal TCK groups run and tracked.                    |
| WP-08        | DMN normalized model and validator.            | WP-00        | DMN parser, model structs, validation                   | Literal model loads into normalized structures.         |
| WP-09        | DMN literal-expression execution path.         | WP-08, WP-05 | executor wiring to FEEL                                 | End-to-end literal-expression TCK case passes.          |
| WP-10        | Decision table engine.                         | WP-09, WP-06 | input evaluation, rule matching, outputs                | Decision-table groups execute with classification.      |
| WP-11        | Hit policy module.                             | WP-10        | all target hit policy reducers                          | Per-policy compatibility reported independently.        |
| WP-12        | Full DMN graph features.                       | WP-11, WP-07 | DRG execution, BKMs, invocations, services              | Advanced DMN groups execute and report coverage.        |
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

## 23. Execution Cadence and Reporting

Track status per work package using this state model:

- `not_started`
- `in_progress`
- `blocked`
- `in_review`
- `done`

Required weekly report fields:

- reporting date;
- current TCK pinned commit;
- work package status table;
- newly passed tests (count);
- newly failed tests (count);
- unsupported count delta;
- top blockers with owner and next action;
- risk changes;
- planned work for next period.

Minimum quality bar before setting any work package to `done`:

- implementation merged;
- unit/integration tests merged;
- TCK impact measured and recorded;
- no unresolved blocker tied to that package;
- requirement mappings updated.

---

## 24. Immediate Next Actions (First Two Iterations)

Iteration A:

1. complete WP-00 and WP-01;
2. scaffold WP-02 case loader with strict error surfacing;
3. implement WP-03 result classification and CSV/JSON report skeleton;
4. demonstrate one end-to-end literal-expression case run and report output.

Iteration B:

1. complete WP-04 parser contract tests;
2. implement WP-05 decimal arithmetic, comparisons, and null/boolean semantics;
3. publish first FEEL core profile report;
4. baseline regression suite for all passing core cases.

This sequence establishes traceability and measurable compatibility early, before broad feature expansion.

---

## 25. Current Progression Status

Status values:

- `done`
- `in_progress`
- `in_review`
- `blocked`
- `not_started`

### 25.1 Phase Status (as of 2026-07-15)

| Phase                                               | Status      | Notes                                                                                                                                               |
| --------------------------------------------------- | ----------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| Phase 0 — Repository and Fork Setup                 | done        | Umbrella created; applications scaffolded; baseline CI and vendored TCK path in place.                                                              |
| Phase 1 — TCK Harness Foundation                    | done        | Loader, runner, comparator, reporter, and `mix tck` task implemented with explicit statuses.                                                        |
| Phase 2 — FEEL Core Compliance                      | done        | Core parser/evaluator semantics validated with passing tests and core profile reporting.                                                           |
| Phase 3 — FEEL Structural Features                  | in_progress | Initial structural support implemented: ranges, unary tests, path/filter, quantifiers, for, and closures.                                         |
| Phase 4 — Built-in Functions and Temporal Semantics | not_started | Planned after structural FEEL features.                                                                                                             |
| Phase 5 — Minimal DMN Execution                     | in_progress | Literal-expression DMN execution path works; continue broadening model coverage.                                                                    |
| Phase 6 — Decision Tables                           | not_started | Awaiting post-core FEEL stabilization.                                                                                                              |
| Phase 7 — Hit Policies                              | not_started | Depends on decision-table engine.                                                                                                                   |
| Phase 8 — Full DMN Graph Features                   | not_started | Depends on earlier DMN phases.                                                                                                                      |

### 25.2 Work Package Status (as of 2026-07-15)

| Work Package | Status      | Evidence                                                                                             |
| ------------ | ----------- | ---------------------------------------------------------------------------------------------------- |
| WP-00        | done        | Umbrella compiles/tests; CI workflow exists.                                                         |
| WP-01        | done        | Vendored snapshot workflow, pin file, update script, and CI pin integrity verification are in place. |
| WP-02        | done        | TCK discovery and case normalization implemented.                                                    |
| WP-03        | done        | Status model and CSV/JSON reporting implemented with metadata.                                       |
| WP-04        | done        | FEEL parser contract tests added and passing.                                                        |
| WP-05        | done        | Core FEEL evaluator semantics and validation baseline are complete and passing.                      |
| WP-06        | in_progress | Implemented ranges, unary tests, path/filter, for, some/every, and function closure execution.      |
| WP-07        | not_started | No temporal/built-in breadth yet.                                                                    |
| WP-08        | in_progress | Normalized model skeleton and parser exist; validation depth still minimal.                          |
| WP-09        | done        | End-to-end DMN literal-expression flow exercised by tests and TCK run.                               |
| WP-10        | not_started | Decision-table execution not implemented yet.                                                        |
| WP-11        | not_started | Hit-policy reducers not implemented yet.                                                             |
| WP-12        | not_started | DRG/BKM/decision-service execution not implemented yet.                                              |
| WP-13        | in_progress | CI and quality gates exist; release-grade regression and pin-integrity gates being hardened.         |
