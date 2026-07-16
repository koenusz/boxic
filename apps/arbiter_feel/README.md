# Arbiter FEEL

FEEL parsing and evaluation for Arbiter.

## Elixir external functions

Trusted application code can expose an allowlisted set of Elixir functions to
FEEL. Model text receives callable names only: it cannot construct module names,
atoms, or arbitrary MFA tuples.

This is Arbiter's platform-native replacement for DMN Java external functions.
Both mechanisms let decisions call trusted host-language code, but the Elixir
registry targets the BEAM rather than JVM classes and reflection. The official
Java-specific TCK group remains unsupported because an Elixir call is not Java
interoperability.

### Define host functions

External functions are ordinary public Elixir functions. For example:

```elixir
defmodule MyApp.Pricing do
  def maximum(left, right), do: max(left, right)

  # A variadic FEEL tail arrives as a list in the final Elixir argument.
  def join(first, rest), do: Enum.join([first | rest], " ")
end
```

### Create an allowlisted registry

Define a registry with the compile-time DSL:

```elixir
defmodule MyApp.DecisionFunctions do
  use Arbiter.FEEL.ExternalFunctions

  external "maximum", {MyApp.Pricing, :maximum},
    parameters: [:integer, :integer],
    returns: :number

  external "joinWords", {MyApp.Pricing, :join},
    parameters: [:string, {:varargs, :string}],
    returns: :string
end
```

Only functions present in this registry are exposed. The DMN model never
receives `{module, function}` values and cannot turn strings into modules or
atoms.

### Boundary types

The `parameters` and `returns` options control conversion at the trusted host
boundary:

| Type | FEEL side | Elixir side |
| ---- | --------- | ----------- |
| `:feel` | Any supported FEEL value | Unchanged Arbiter value |
| `:number` | Number | `Decimal` |
| `:integer` | Integral number | Integer; returned integers become `Decimal` |
| `:float` | Number | Float; returned floats become `Decimal` |
| `:string` | String | UTF-8 binary |
| `:char` | One-codepoint string | Unicode codepoint integer |
| `:boolean` | Boolean | Boolean |

An empty `parameters` list performs no argument conversion or arity check. A
final `{:varargs, type}` accepts any additional FEEL arguments, converts them,
and passes them as a list in the final Elixir argument.

### Call from FEEL

Use the registry directly with FEEL:

```elixir
context =
  MyApp.DecisionFunctions
  |> Arbiter.FEEL.ExternalFunctions.to_context()

{:ok, maximum} = Arbiter.FEEL.evaluate("maximum(123, 456)", context)
{:ok, "foo bar baz"} =
  Arbiter.FEEL.evaluate(~S|joinWords("foo", "bar", "baz")|, context)
```

Registered context names take precedence over FEEL built-ins, so applications
may deliberately replace a built-in for a particular evaluation.

### Call from DMN

The DMN literal expression calls the registered name normally:

```xml
<decision id="price" name="Price">
  <literalExpression>
    <text>maximum(requested price, price ceiling)</text>
  </literalExpression>
</decision>
```

Supply the registry separately when evaluating the trusted model. The registry
is host configuration and is not encoded in DMN XML:

```elixir
Arbiter.DMN.evaluate(model, "Price", inputs,
  external_functions: MyApp.DecisionFunctions
)
```

The registry module or an `Arbiter.FEEL.ExternalFunctions` registry value may be
passed through `:external_functions`.

### Errors and trust boundary

Invalid arity, argument conversion failures, invalid return values, and
exceptions raised by host code become structured `Arbiter.FEEL.Error` values.
External functions execute in the evaluator process, so application code should
keep them deterministic and fast and should add its own timeout or isolation
when calling remote services.

Do not construct registry entries from model content or untrusted strings. The
registry must remain trusted application configuration; this is what prevents
the feature from becoming arbitrary BEAM code execution.

This replacement is an Arbiter Elixir extension, not an implementation of
DMN's Java external-function binding. The official Java-specific TCK group is
therefore still selected and explicitly reported as unsupported.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `arbiter_feel` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:arbiter_feel, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/arbiter_feel>.
