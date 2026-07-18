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
  @spec load_xml(String.t()) :: {:ok, Model.t()} | {:error, load_error()}
  defdelegate load_xml(xml), to: Loader

  @doc """
  Validates a normalized DMN model.

      with {:ok, model} <- Boxic.DMN.load_xml(xml) do
        Boxic.DMN.validate(model)
      end
  """
  @spec validate(Model.t()) :: :ok | {:error, [validation_error()]}
  defdelegate validate(model), to: Validator

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
end
