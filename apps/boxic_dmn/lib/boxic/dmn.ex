defmodule Boxic.DMN do
  @moduledoc """
  Loads, validates, and evaluates DMN models.

  Use `load_file/1` when the input is a path and `load_xml/1` when the input is
  XML. `load/1` remains available for backwards compatibility and dispatches
  XML-looking input to `load_xml/1`; all other input is treated as a path.
  """

  alias Boxic.DMN.Model
  alias Boxic.DMN.{Evaluator, Validator}
  alias Boxic.DMN.XML.Loader
  alias Boxic.DMN.XML.SchemaValidator
  alias Boxic.DMN.XML.Writer

  @typedoc "An error returned while reading or decoding a DMN document."
  @type load_error ::
          {:file_error, Path.t(), File.posix()}
          | :invalid_xml
          | :trailing_xml_content
          | :invalid_definitions_document

  @typedoc "A structural problem found while validating a normalized model."
  @type validation_error ::
          {atom(), term()}
          | {atom(), term(), term()}
          | {atom(), term(), term(), term()}

  @typedoc "An error produced while resolving or evaluating a decision."
  @type evaluation_error ::
          Boxic.FEEL.Error.t()
          | {atom(), term()}
          | {atom(), term(), term()}
          | {atom(), term(), term(), term()}

  @doc """
  Loads a DMN document from either an XML string or a file path.

  New code should prefer `load_xml/1` or `load_file/1`, which avoid input
  ambiguity.

      Boxic.DMN.load("<definitions id=\"example\" namespace=\"urn:example\"/>")
  """
  @spec load(String.t()) :: {:ok, Model.t()} | {:error, load_error()}
  @deprecated "use load_xml/1, load_xml/2, or load_file/1"
  defdelegate load(path_or_xml), to: Loader

  @doc """
  Loads a DMN document and its sibling imports from `path`.

      Boxic.DMN.load_file("priv/decisions/pricing.dmn")
  """
  @spec load_file(Path.t()) :: {:ok, Model.t()} | {:error, load_error()}
  defdelegate load_file(path), to: Loader

  @doc """
  Loads a DMN document from an XML string.

      Boxic.DMN.load_xml("<definitions id=\"example\" namespace=\"urn:example\"/>")
  """
  @spec load_xml(String.t()) ::
          {:ok, Model.t()} | {:error, load_error() | [Boxic.DMN.Diagnostic.t()]}
  defdelegate load_xml(xml), to: Loader

  @doc "Loads DMN XML using only an explicitly supplied import map or resolver."
  @spec load_xml(String.t(), keyword()) ::
          {:ok, Model.t()} | {:error, load_error() | [Boxic.DMN.Diagnostic.t()]}
  defdelegate load_xml(xml, opts), to: Loader

  @doc """
  Inspects a well-formed DMN document without claiming schema validity,
  executability, or writability.
  """
  @spec inspect_xml(String.t()) ::
          {:ok, Model.t()} | {:error, load_error() | [Boxic.DMN.Diagnostic.t()]}
  defdelegate inspect_xml(xml), to: Loader

  @doc "Validates XML against the packaged normative DMN 1.5 schema family."
  @spec validate_xml_schema(String.t()) :: :ok | {:error, [Boxic.DMN.Diagnostic.t()]}
  defdelegate validate_xml_schema(xml), to: SchemaValidator, as: :validate

  @doc """
  Validates a normalized DMN model.

      with {:ok, model} <- Boxic.DMN.load_xml(xml) do
        Boxic.DMN.validate(model)
      end
  """
  @spec validate(Model.t()) :: :ok | {:error, [validation_error()]}
  defdelegate validate(model), to: Validator

  @doc """
  Validates an existing model for one public capability.

  Supported capabilities are `:evaluation`, `:serialization`, and `:authoring`.
  This form returns stable `Boxic.DMN.Diagnostic` values.
  """
  @spec validate(Model.t(), keyword()) :: :ok | {:error, [Boxic.DMN.Diagnostic.t()]}
  defdelegate validate(model, opts), to: Validator

  @doc """
  Encodes a normalized DMN model as deterministic DMN XML.

  The model must originate from the pinned DMN profile and have complete
  serialization fidelity. Supported options are:

    * `:format` — `:pretty` (default) or `:compact`;
    * `:xml_declaration` — whether to emit the UTF-8 XML declaration, defaulting
      to `true`.

  Pretty output uses two-space indentation, LF line endings, and one final
  newline. Compact output contains no presentation whitespace. FEEL text is
  escaped but otherwise preserved.
  """
  @spec encode_xml(Model.t(), keyword()) ::
          {:ok, String.t()} | {:error, [Boxic.DMN.SerializationError.t()]}
  def encode_xml(model, opts \\ []), do: Writer.encode(model, opts)

  @doc """
  Checks whether a normalized model can be encoded without data loss.

  This runs the same model, option, version, fidelity, identifier, reference,
  and unsupported-expression checks as `encode_xml/2` without producing XML.
  """
  @spec validate_serializable(Model.t(), keyword()) ::
          :ok | {:error, [Boxic.DMN.SerializationError.t()]}
  def validate_serializable(model, opts \\ []), do: Writer.validate_serializable(model, opts)

  @doc """
  Evaluates a named decision using the supplied input context.

      Boxic.DMN.evaluate(model, "Price", %{"quantity" => Decimal.new("2")})
  """
  @spec evaluate(Model.t(), String.t(), map()) ::
          {:ok, term()} | {:error, evaluation_error()}
  def evaluate(model, decision_name, context \\ %{}),
    do: Evaluator.evaluate(model, decision_name, context)

  @doc """
  Evaluates a named decision with evaluator options.

      Boxic.DMN.evaluate(model, "Price", inputs,
        external_functions: MyApp.DecisionFunctions
      )
  """
  @spec evaluate(Model.t(), String.t(), map(), keyword()) ::
          {:ok, term()} | {:error, evaluation_error()}
  defdelegate evaluate(model, decision_name, context, opts), to: Evaluator

  @doc """
  Evaluates a named decision service.

      Boxic.DMN.evaluate_service(model, "Pricing Service", %{"order" => order})
  """
  @spec evaluate_service(Model.t(), String.t(), map() | list()) ::
          {:ok, term()} | {:error, evaluation_error()}
  defdelegate evaluate_service(model, service_name, arguments), to: Evaluator

  @doc "Evaluates a decision service with the same trusted host-function options as `evaluate/4`."
  @spec evaluate_service(Model.t(), String.t(), map() | list(), keyword()) ::
          {:ok, term()} | {:error, evaluation_error()}
  defdelegate evaluate_service(model, service_name, arguments, opts), to: Evaluator
end
