defmodule Boxic.FEEL.ExternalFunctions do
  @moduledoc """
  Allowlisted Elixir functions exposed to FEEL evaluation.

  Registries are constructed by trusted application code. FEEL and DMN model
  text can invoke registered names, but cannot resolve modules, functions, or
  atoms itself.
  """

  alias Boxic.FEEL.Error

  defstruct entries: %{}

  @type boundary_type :: :feel | :number | :integer | :float | :string | :char | :boolean
  @type callable :: function() | {module(), atom()}
  @type entry :: %{
          callable: callable(),
          parameters: [boundary_type() | {:varargs, boundary_type()}],
          returns: boundary_type()
        }
  @type t :: %__MODULE__{entries: %{optional(String.t()) => entry()}}

  @doc """
  Adds the external-function registry DSL to a module.

      use Boxic.FEEL.ExternalFunctions
  """
  defmacro __using__(_opts) do
    quote do
      import Boxic.FEEL.ExternalFunctions, only: [external: 2, external: 3]
      Module.register_attribute(__MODULE__, :boxic_external_functions, accumulate: true)
      @before_compile Boxic.FEEL.ExternalFunctions
    end
  end

  @doc """
  Registers an allowlisted host function in a registry module.

      external "maximum", {MyApp.Math, :maximum},
        parameters: [:number, :number],
        returns: :number
  """
  defmacro external(name, callable, opts \\ []) do
    quote bind_quoted: [name: name, callable: callable, opts: opts] do
      @boxic_external_functions {name, callable, opts}
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    entries = Module.get_attribute(env.module, :boxic_external_functions) |> Enum.reverse()

    quote do
      @doc "Returns this module's compiled external-function registry."
      def external_functions do
        Boxic.FEEL.ExternalFunctions.new(unquote(Macro.escape(entries)))
      end
    end
  end

  @doc """
  Creates a registry, optionally from `{name, callable, options}` entries.

      Boxic.FEEL.ExternalFunctions.new([
        {"maximum", {MyApp.Math, :maximum}, parameters: [:number, :number]}
      ])
  """
  @spec new([{String.t(), callable(), keyword()}]) :: t()
  def new(entries \\ []) do
    Enum.reduce(entries, %__MODULE__{}, fn {name, callable, opts}, registry ->
      register(registry, name, callable, opts)
    end)
  end

  @doc """
  Adds or replaces one allowlisted function.

      Boxic.FEEL.ExternalFunctions.register(
        registry,
        "maximum",
        {MyApp.Math, :maximum},
        parameters: [:number, :number],
        returns: :number
      )
  """
  @spec register(t(), String.t(), callable(), keyword()) :: t()
  def register(%__MODULE__{} = registry, name, callable, opts \\ [])
      when is_binary(name) and (is_function(callable) or is_tuple(callable)) do
    entry = %{
      callable: callable,
      parameters: Keyword.get(opts, :parameters, []),
      returns: Keyword.get(opts, :returns, :feel)
    }

    %{registry | entries: Map.put(registry.entries, name, entry)}
  end

  @doc """
  Compatibility adapter that merges a registry into a FEEL context.

  New code should pass `external_functions:` to `Boxic.FEEL.evaluate/3`.
  """
  @deprecated "pass external_functions: to Boxic.FEEL.evaluate/3 instead"
  @spec to_context(t() | module()) :: map()
  def to_context(module) when is_atom(module), do: module.external_functions() |> to_context()

  def to_context(%__MODULE__{entries: entries}) do
    Map.new(entries, fn {name, _entry} ->
      {name,
       {:external_function, fn args -> invoke(%__MODULE__{entries: entries}, name, args) end}}
    end)
  end

  @doc false
  def attach(context, registry, precedence \\ :builtins)
      when is_map(context) and precedence in [:builtins, :registered] do
    registry = if is_atom(registry), do: registry.external_functions(), else: registry
    Map.put(context, __MODULE__, {registry, precedence})
  end

  @doc false
  def resolve(context, name) when is_map(context) and is_binary(name) do
    builtin =
      case Boxic.FEEL.Builtins.resolve(name) do
        {:ok, nil} -> :error
        found -> found
      end

    case Map.get(context, __MODULE__) do
      {%__MODULE__{entries: entries} = registry, precedence} ->
        external =
          if Map.has_key?(entries, name) do
            {:ok, {:external_function, fn args -> invoke(registry, name, args) end}}
          else
            :error
          end

        case {precedence, external, builtin} do
          {:registered, {:ok, _} = found, _builtin} -> found
          {_precedence, _external, {:ok, _} = found} -> found
          {_precedence, {:ok, _} = found, _builtin} -> found
          _ -> :error
        end

      _ ->
        builtin
    end
  end

  @doc """
  Invokes a registered function after applying its boundary conversions.

      Boxic.FEEL.ExternalFunctions.invoke(registry, "maximum", [
        Decimal.new("1"),
        Decimal.new("2")
      ])
  """
  @spec invoke(t(), String.t(), [term()]) :: {:ok, term()} | {:error, Error.t()}
  def invoke(%__MODULE__{entries: entries}, name, args) do
    with {:ok, entry} <- fetch_entry(entries, name),
         {:ok, converted} <- convert_arguments(args, entry.parameters),
         {:ok, result} <- call(entry.callable, converted),
         {:ok, result} <- from_elixir(result, entry.returns) do
      {:ok, result}
    end
  end

  defp fetch_entry(entries, name) do
    case Map.fetch(entries, name) do
      {:ok, entry} ->
        {:ok, entry}

      :error ->
        {:error,
         Error.new(:unknown_function, "external function #{inspect(name)} is not registered")}
    end
  end

  defp convert_arguments(args, []), do: {:ok, args}

  defp convert_arguments(args, parameters) do
    case List.last(parameters) do
      {:varargs, type} ->
        fixed = Enum.drop(parameters, -1)

        if length(args) < length(fixed) do
          {:error, Error.new(:arity_error, "external function called with invalid arity")}
        else
          {fixed_args, rest_args} = Enum.split(args, length(fixed))

          with {:ok, fixed_values} <- convert_typed_arguments(fixed_args, fixed),
               {:ok, rest_values} <-
                 convert_typed_arguments(rest_args, List.duplicate(type, length(rest_args))) do
            {:ok, fixed_values ++ [rest_values]}
          end
        end

      _type when length(args) == length(parameters) ->
        convert_typed_arguments(args, parameters)

      _type ->
        {:error, Error.new(:arity_error, "external function called with invalid arity")}
    end
  end

  defp convert_typed_arguments(args, types) do
    args
    |> Enum.zip(types)
    |> Enum.reduce_while({:ok, []}, fn {value, type}, {:ok, converted} ->
      case to_elixir(value, type) do
        {:ok, value} -> {:cont, {:ok, converted ++ [value]}}
        {:error, %Error{} = error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp to_elixir(value, :feel), do: {:ok, value}
  defp to_elixir(%Decimal{} = value, :number), do: {:ok, value}
  defp to_elixir(%Decimal{} = value, :integer), do: decimal_integer(value)
  defp to_elixir(%Decimal{} = value, :float), do: {:ok, Decimal.to_float(value)}
  defp to_elixir(value, :string) when is_binary(value), do: {:ok, value}
  defp to_elixir(<<codepoint::utf8>>, :char), do: {:ok, codepoint}
  defp to_elixir(value, :boolean) when is_boolean(value), do: {:ok, value}

  defp to_elixir(_value, type),
    do: {:error, Error.new(:type_error, "value cannot be converted to #{type}")}

  defp decimal_integer(value) do
    rounded = Decimal.round(value, 0)

    if Decimal.equal?(value, rounded) do
      {:ok, Decimal.to_integer(rounded)}
    else
      {:error, Error.new(:type_error, "number is not an integer")}
    end
  end

  defp call(function, args) when is_function(function, length(args)),
    do: safe_call(fn -> apply(function, args) end)

  defp call({module, function}, args), do: safe_call(fn -> apply(module, function, args) end)

  defp call(_callable, _args),
    do: {:error, Error.new(:arity_error, "external function called with invalid arity")}

  defp safe_call(callback) do
    {:ok, callback.()}
  rescue
    _exception ->
      {:error, Error.new(:external_function_error, "registered external function failed")}
  catch
    _kind, _reason ->
      {:error, Error.new(:external_function_error, "registered external function failed")}
  end

  defp from_elixir(value, :feel), do: {:ok, value}
  defp from_elixir(%Decimal{} = value, :number), do: {:ok, value}
  defp from_elixir(value, :number) when is_integer(value), do: {:ok, Decimal.new(value)}
  defp from_elixir(value, :number) when is_float(value), do: {:ok, Decimal.from_float(value)}
  defp from_elixir(value, :integer) when is_integer(value), do: {:ok, Decimal.new(value)}
  defp from_elixir(value, :float) when is_float(value), do: {:ok, Decimal.from_float(value)}
  defp from_elixir(value, :string) when is_binary(value), do: {:ok, value}
  defp from_elixir(value, :char) when is_integer(value), do: {:ok, <<value::utf8>>}
  defp from_elixir(value, :boolean) when is_boolean(value), do: {:ok, value}

  defp from_elixir(_value, type),
    do: {:error, Error.new(:type_error, "external return value does not conform to #{type}")}
end
