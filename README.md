# Boxic

**Boxic** abbreviates **boxed logic**: business rules captured in explicit,
portable boxes instead of being scattered through application code. The name
also nods to DMN's boxed expressions—decision tables, contexts, relations, and
other visual forms that make executable decisions understandable.

Boxic is a native Elixir implementation of the Decision Model and Notation
(DMN) 1.4 standard and its Friendly Enough Expression Language (FEEL). It is an
umbrella project containing:

- `boxic_feel`, the FEEL parser, evaluator, standard library, and Elixir
  external-function boundary;
- `boxic_dmn`, the DMN XML loader, validator, and decision evaluator; and
- `boxic_dmn_tck`, the internal compatibility harness for the official DMN
  Technology Compatibility Kit (TCK).

## Quick start

```bash
mix deps.get
mix test
```

Evaluate FEEL directly:

```elixir
{:ok, result} =
  Boxic.FEEL.evaluate(
    "for customer in customers return customer.name",
    %{"customers" => [%{"name" => "Ada"}, %{"name" => "Grace"}]}
  )

# result == ["Ada", "Grace"]
```

Load and evaluate a DMN model:

```elixir
{:ok, model} = Boxic.DMN.load("priv/decisions/pricing.dmn")
:ok = Boxic.DMN.validate(model)

{:ok, price} =
  Boxic.DMN.evaluate(model, "Final Price", %{
    "List Price" => Decimal.new("125.00"),
    "Customer Tier" => "gold"
  })
```

All public operations return tagged tuples. Parsing, validation, conversion,
reference-resolution, and evaluation failures are values rather than uncaught
model exceptions.

## FEEL reference

Boxic parses FEEL text into a validated AST and evaluates it using decimal
number semantics and FEEL's three-valued logic. Use `Boxic.FEEL.parse/1` when
you need the AST, `evaluate/2` for ordinary expressions,
`evaluate_ast/2` for a previously parsed tree, and `evaluate_unary_test/3` for
decision-table style tests.

### Values and literals

Supported values include:

- arbitrary-precision numbers backed by `Decimal`;
- strings, booleans, and `null`;
- lists and contexts;
- inclusive and exclusive ranges;
- dates, times, date-times, year-month durations, and day-time durations;
- functions and lexical closures.

```elixir
Boxic.FEEL.evaluate(~S|{name: "Ada", scores: [8, 13, 21], active: true}|)
Boxic.FEEL.evaluate("[1..10]")
Boxic.FEEL.evaluate(~S|date and time("2025-03-30T01:30:00@Europe/Amsterdam")|)
Boxic.FEEL.evaluate(~S|duration("P1Y2M")|)
```

Temporal values support construction, comparison, extraction, arithmetic, ISO
8601 offsets, IANA named zones, and daylight-saving transitions.

### Operators and control flow

The expression language supports:

- arithmetic (`+`, `-`, `*`, `/`, `**`) and unary signs;
- equality, ordering, `between`, `in`, and `instance of`;
- `and`, `or`, and `not` with FEEL null propagation;
- `if ... then ... else ...` conditionals;
- line and block comments;
- multiword identifiers and context/path navigation.

```elixir
{:ok, discounted} =
  Boxic.FEEL.evaluate("if subtotal > 100 then subtotal * 0.9 else subtotal", %{
    "subtotal" => Decimal.new(120)
  })

# Decimal.equal?(discounted, Decimal.new(108))

{:ok, true} = Boxic.FEEL.evaluate("7 between 1 and 10")
{:ok, nil} = Boxic.FEEL.evaluate("null and true")
```

### Collections, paths, and iteration

Lists can be projected with paths, filtered by position or predicate, iterated
with one or more `for` bindings, and tested with `some` and `every`.

```elixir
context = %{
  "orders" => [
    %{"customer" => "Ada", "total" => Decimal.new(120)},
    %{"customer" => "Grace", "total" => Decimal.new(80)}
  ]
}

{:ok, ["Ada"]} = Boxic.FEEL.evaluate("orders[total >= 100].customer", context)
{:ok, doubled_totals} =
  Boxic.FEEL.evaluate("for order in orders return order.total * 2", context)
# Enum.map(doubled_totals, &Decimal.to_integer/1) == [240, 160]
{:ok, true} = Boxic.FEEL.evaluate("some order in orders satisfies order.total > 100", context)
```

### Contexts and functions

Context entries are evaluated in order and may refer to preceding entries.
Functions capture their surrounding context, accept positional or named
arguments, and may be called recursively through DMN business knowledge
models.

```elixir
{:ok, answer} =
  Boxic.FEEL.evaluate("{base: 40, add: function(n) base + n, answer: add(2)}.answer")
# Decimal.equal?(answer, Decimal.new(42))

{:ok, sum} =
  Boxic.FEEL.evaluate("(function(left, right) left + right)(left: 3, right: 5)")
# Decimal.equal?(sum, Decimal.new(8))
```

### Unary tests and ranges

Unary tests include wildcards, comparison tests, ranges, comma-separated test
lists, and negation. Range boundaries may be open or closed.

```elixir
{:ok, true} = Boxic.FEEL.evaluate_unary_test(">= 18", Decimal.new(21))
{:ok, true} = Boxic.FEEL.evaluate_unary_test("[18..65]", Decimal.new(42))
{:ok, false} = Boxic.FEEL.evaluate_unary_test("not(2)", Decimal.new(2))
```

### Built-in functions

Boxic implements the FEEL built-ins exercised by its Level 3 compatibility
profile. Names below use Elixir-friendly underscores; FEEL source may use the
standard spaced names such as `string length` and `date and time`.

| Family | Functions |
| --- | --- |
| String and regex | `string_length`, `upper_case`, `lower_case`, `substring`, `substring_before`, `substring_after`, `contains`, `starts_with`, `ends_with`, `split`, `replace`, `matches`, `string_join` |
| Lists | `list_contains`, `list_replace`, `count`, `append`, `concatenate`, `insert_before`, `remove`, `reverse`, `sort`, `index_of`, `union`, `distinct_values`, `flatten`, `sublist` |
| Numeric and statistics | `sum`, `min`, `max`, `mean`, `product`, `median`, `mode`, `stddev`, `abs`, `sqrt`, `exp`, `log`, `modulo`, `even`, `odd` |
| Rounding | `round`, `floor`, `ceiling`, `decimal`, `round_up`, `round_down`, `round_half_up`, `round_half_down` |
| Boolean | `all`, `any` |
| Context | `get_value`, `get_entries`, `context`, `context_put`, `context_merge`, `is` |
| Conversion and temporal | `string`, `number`, `date`, `time`, `date_time`, `duration`, `range`, `now`, `today`, `day_of_year`, `day_of_week`, `month_of_year`, `week_of_year`, `years_and_months_duration` |
| Interval relations | `before`, `after`, `meets`, `met_by`, `overlaps_before`, `overlaps_after`, `finishes`, `finished_by`, `includes`, `during`, `starts`, `started_by`, `coincides`, `overlaps` |

```elixir
{:ok, "BOXED LOGIC"} = Boxic.FEEL.evaluate(~S|upper case("boxed logic")|)
{:ok, mean} = Boxic.FEEL.evaluate("mean([1, 2, 3, 4])")
# Decimal.equal?(mean, Decimal.new("2.5"))
{:ok, distinct} = Boxic.FEEL.evaluate("distinct values([1, 2, 1, 3])")
# Enum.map(distinct, &Decimal.to_integer/1) == [1, 2, 3]
```

### Elixir external functions

Boxic replaces Java reflection with an explicit, allowlisted BEAM integration.
Trusted applications can register Elixir functions with typed argument and
return conversion, variadic parameters, built-in shadowing, and structured
error handling, then inject that registry into FEEL or DMN evaluation. Model
text cannot resolve arbitrary modules, atoms, or functions.

```elixir
defmodule MyApp.DecisionFunctions do
  use Boxic.FEEL.ExternalFunctions

  external "risk score", {MyApp.Risk, :score},
    parameters: [:integer, :string],
    returns: :number
end

context = Boxic.FEEL.ExternalFunctions.to_context(MyApp.DecisionFunctions)
Boxic.FEEL.evaluate(~S|risk score(42, "gold")|, context)

Boxic.DMN.evaluate(model, "Risk", inputs,
  external_functions: MyApp.DecisionFunctions
)
```

See the [external-function guide](apps/boxic_feel/README.md#elixir-external-functions)
for boundary types, variadic functions, trust guidance, and complete examples.

## DMN reference

`Boxic.DMN.load/1` accepts either a DMN XML string or a file path. Loading
normalizes XML namespaces into stable Elixir model structs; `validate/1`
checks structural and reference integrity before execution. File-based loading
also resolves namespace imports from sibling `.dmn` files.

### Supported model features

- DMN 1.4 namespace-qualified definitions and metadata;
- input data, item definitions, nested components, collections, and allowed
  values;
- decisions and information requirements with dependency ordering, memoization,
  and cycle detection;
- literal expressions and the full FEEL evaluator described above;
- boxed contexts, lists, relations, conditionals, filters, and iterators;
- invocations, function definitions, and recursive business knowledge models;
- decision services with named or positional arguments;
- namespace imports and qualified references across models;
- typed input coercion, including recursively typed collections and contexts;
- normalized multiword and punctuation-bearing FEEL names;
- multiple-output decision tables, output defaults, allowed output values, and
  rule annotations.

### Decision tables

All standard hit policies are supported:

| Hit policy | Result |
| --- | --- |
| `UNIQUE` | Exactly one rule may match. |
| `FIRST` | Returns the first matching rule. |
| `ANY` | Multiple matches are allowed when their outputs agree. |
| `PRIORITY` | Returns the highest-priority allowed output. |
| `RULE ORDER` | Returns matches in rule order. |
| `OUTPUT ORDER` | Returns matches in output-priority order. |
| `COLLECT` | Returns every match, optionally aggregated with `SUM`, `MIN`, `MAX`, or `COUNT`. |

For example, a compact unique table can select a discount:

```xml
<decision id="discount" name="Discount">
  <variable name="Discount" typeRef="number"/>
  <decisionTable hitPolicy="UNIQUE">
    <input><inputExpression typeRef="string"><text>Customer Tier</text></inputExpression></input>
    <output name="rate" typeRef="number"/>
    <rule><inputEntry><text>"gold"</text></inputEntry><outputEntry><text>0.20</text></outputEntry></rule>
    <rule><inputEntry><text>-</text></inputEntry><outputEntry><text>0.00</text></outputEntry></rule>
  </decisionTable>
</decision>
```

Evaluation resolves the decision by DMN ID or name and supplies inputs by DMN
name:

```elixir
{:ok, model} = Boxic.DMN.load(xml)
{:ok, %{"rate" => Decimal.new("0.20")}} =
  Boxic.DMN.evaluate(model, "Discount", %{"Customer Tier" => "gold"})
```

### Boxed expressions and services

Boxic executes boxed expressions recursively. Context entries can combine
intermediate decisions; relations return rows as contexts; filters and
iterators operate on lists; invocations bind arguments to BKMs and decision
services.

```elixir
{:ok, result} = Boxic.DMN.evaluate(model, "Eligibility", application)

{:ok, outputs} =
  Boxic.DMN.evaluate_service(model, "Underwriting Service", %{
    "Applicant" => applicant,
    "Requested amount" => Decimal.new(25_000)
  })
```

Validation reports malformed XML, invalid definitions, duplicate IDs or names,
unresolved references, empty expressions, malformed table rules, unsupported
policies, invalid aggregations, and invalid decision-service references.

## Testing and compliance

Boxic uses three complementary test layers:

1. Ordinary ExUnit tests cover parser and evaluator semantics, boundary and
   error behavior, DMN loading and validation, decision execution, imports,
   decision services, and the Elixir external-function extension.
2. The strict TCK profiles execute every applicable official FEEL and DMN case
   and compare normalized Boxic values with the expected upstream result.
3. CI regenerates JSON reports and compares pass counts, compatibility,
   coverage, and the pinned TCK revision against committed baselines. A nightly
   workflow also retains complete CSV and JSON corpus reports.

Run the same checks locally:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test

mix tck --suite feel --profile implemented
mix tck --suite dmn --profile implemented
mix tck --all --soft-fail --report artifacts/tck-full --format both
```

### Current compatibility report

The committed reports were generated on Elixir 1.19.1 / OTP 28 against DMN
1.4 TCK commit `0dbcaf9b98bc3af4e36d44a7aed95e9e85703a13`.

| Suite | Passed | Unsupported | Failed / missing / error | Suite coverage | Supported-scope compatibility |
| --- | ---: | ---: | ---: | ---: | ---: |
| FEEL | 2,042 | 18 | 0 | 99.13% | 100% |
| DMN | 1,485 | 0 | 0 | 100% | 100% |
| Combined | 3,527 | 18 | 0 | 99.49% | 100% |

These results provide strong evidence that Boxic implements DMN **compliance
level 3**: it executes the Level 3 FEEL language and boxed-expression cases,
as well as the Level 1 and Level 2 cases beneath them. This is a tested
compatibility claim against the pinned official corpus, not a claim of formal
OMG certification.

The sole exception is the 18-case `0076-feel-external-java` group. Those cases
specifically require JVM class lookup, Java method signatures, primitive
conversion, and reflection. Boxic runs natively on the BEAM and deliberately
reports them as `unsupported`; they are never skipped or counted as passing.
The allowlisted Elixir external-function registry supplies the equivalent host
integration for Elixir applications without pretending to implement Java
interop.

The source reports are
[`compatibility/feel-implemented-0dbcaf9b.json`](compatibility/feel-implemented-0dbcaf9b.json)
and
[`compatibility/dmn-implemented-0dbcaf9b.json`](compatibility/dmn-implemented-0dbcaf9b.json).
See [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) for the compatibility delta and
release procedure.

## Acknowledgements

Boxic's compatibility work is made possible by the
[DMN Technology Compatibility Kit](https://github.com/dmn-tck/tck), maintained
by the DMN TCK community. The repository vendors a pinned snapshot of that
suite under `vendor/dmn-tck`; `PINNED_COMMIT` records the exact upstream
revision so results remain reproducible. We are grateful to the contributors
who created and maintain its models, expected results, runner conventions, and
compliance-level organization.

DMN and FEEL are standards of the
[Object Management Group](https://www.omg.org/dmn/). Boxic is an independent
implementation and is not affiliated with or endorsed by the OMG or the DMN
TCK project.
