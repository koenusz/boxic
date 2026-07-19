# Boxic DMN

Boxic DMN is a native Elixir loader, validator, and evaluator for Decision
Model and Notation (DMN) 1.4 models. It uses `boxic_feel` for expression
evaluation and does not require a JVM.

## Installation

Add `boxic_dmn` to `mix.exs`:

```elixir
def deps do
  [
    {:boxic_dmn, "~> 0.2.0"}
  ]
end
```

## Quick start

Load XML explicitly, validate its normalized model, and evaluate a decision:

```elixir
xml = """
<definitions id="example" name="Example" namespace="https://example.com/boxic">
  <decision id="greeting" name="Greeting">
    <literalExpression>
      <text>"Hello " + name</text>
    </literalExpression>
  </decision>
</definitions>
"""

with {:ok, model} <- Boxic.DMN.load_xml(xml),
     :ok <- Boxic.DMN.validate(model),
     {:ok, greeting} <- Boxic.DMN.evaluate(model, "Greeting", %{"name" => "Ada"}) do
  greeting
end
```

Use `Boxic.DMN.load_file/1` for a filesystem path. It discovers sibling
`.dmn` documents needed for namespace imports. The compatibility
`Boxic.DMN.load/1` function accepts either XML-looking input or a path, but the
explicit functions provide clearer errors.

Loading returns `{:ok, %Boxic.DMN.Model{}}` or a documented load error.
Validation returns `:ok` or `{:error, errors}`. Evaluation returns
`{:ok, value}` or `{:error, reason}`.

## Edit and export decision tables

`Boxic.DMN.Authoring.DecisionTable` provides immutable, ID-based operations for
the structural edits a decision-table UI commonly performs. For example:

```elixir
alias Boxic.DMN.Authoring.DecisionTable, as: Authoring

with {:ok, model} <- Boxic.DMN.load_xml(xml),
     {:ok, model} <-
       Authoring.put_input_entry(model,
         decision_id: "eligibility",
         rule_id: "adult",
         input_id: "customer_age",
         text: ">= 18"
       ),
     :ok <- Boxic.DMN.validate(model),
     {:ok, written_xml} <- Boxic.DMN.encode_xml(model) do
  written_xml
end
```

Adding, removing, or moving an input or output clause updates the corresponding
entry position in every rule. The caller provides stable IDs; Boxic does not
generate random identifiers. UI-only draft, selection, undo, and persistence
state remains an application concern.

`encode_xml/2` emits deterministic DMN 1.4 XML. Its options are:

```elixir
[format: :pretty | :compact, xml_declaration: true | false]
```

The defaults are pretty two-space output with an XML declaration, LF line
endings, and one final newline. `Boxic.DMN.validate_serializable/2` performs the
same preflight checks without producing XML.

The writer guarantees semantic rather than byte-identical source
round-tripping. A loaded model is rejected when its DMN version differs from
the pinned output version or when the loader detected content it could not
retain, such as unsupported extensions or DMNDI. This prevents an edit/export
workflow from silently discarding authored content.

Focused writer performance can be measured without adding work to the ordinary
test suite:

```console
mix run bench/xml_writer_bench.exs
```

The benchmark covers 100, 1,000, and 10,000-rule tables and reports elapsed
time, output size, and process memory.

Maintainers building or publishing this umbrella child as a Hex package must
select the published `boxic_feel` dependency rather than the local sibling:

```console
BOXIC_DMN_HEX_BUILD=true mix hex.build
BOXIC_DMN_HEX_BUILD=true mix hex.publish
```

## Compatibility

Boxic targets DMN 1.4. Against the vendored official DMN Technology
Compatibility Kit revision `0dbcaf9b98bc3af4e36d44a7aed95e9e85703a13`, the
DMN suite passes all 1,485 selected cases. This result covers the DMN suite;
the separate FEEL suite is reported by `boxic_feel`.

The distinct XML-writer audit covers 69 models in that implemented profile.
The vendored files use the newer `20230324` DMN namespace, so all 69 are
explicitly rejected with `:dmn_version_mismatch`; none fail unexpectedly and
none are implicitly converted to the pinned `20211108` DMN 1.4 output.

Java external-function integration is intentionally not implemented because
Boxic runs on the BEAM rather than the JVM. Trusted host functions can instead
be exposed through `Boxic.FEEL.ExternalFunctions`.

## External functions and trust

Pass an allowlisted external-function registry when evaluating:

```elixir
Boxic.DMN.evaluate(model, "Price", inputs,
  external_functions: MyApp.DecisionFunctions
)
```

Registry entries execute application code in the evaluator process. Construct
registries only from trusted application configuration, never from model
content or untrusted strings. Applications should isolate or time-limit
functions that perform remote or long-running work.

## License

Boxic DMN is licensed under Apache-2.0. The official TCK corpus and local
compatibility artifacts are not included in the Hex package.
