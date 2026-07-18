# Boxic DMN

Boxic DMN is a native Elixir loader, validator, and evaluator for Decision
Model and Notation (DMN) 1.4 models. It uses `boxic_feel` for expression
evaluation and does not require a JVM.

## Installation

Add `boxic_dmn` to `mix.exs`:

```elixir
def deps do
  [
    {:boxic_dmn, "~> 0.1.0"}
  ]
end
```

## Quick start

Load XML explicitly, validate its normalized model, and evaluate a decision:

```elixir
xml = """
<definitions id="example" namespace="https://example.com/boxic">
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

## Compatibility

Boxic targets DMN 1.4. Against the vendored official DMN Technology
Compatibility Kit revision `0dbcaf9b98bc3af4e36d44a7aed95e9e85703a13`, the
DMN suite passes all 1,485 selected cases. This result covers the DMN suite;
the separate FEEL suite is reported by `boxic_feel`.

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
