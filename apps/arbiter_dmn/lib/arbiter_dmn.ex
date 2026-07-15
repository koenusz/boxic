defmodule Arbiter.DMN do
  @moduledoc """
  Minimal DMN entry point for Iteration A.

  Supports loading DMN XML with literal expressions and evaluating a decision by name.
  """

  alias Arbiter.DMN.Model

  @spec load(String.t()) :: {:ok, Model.t()} | {:error, term()}
  def load(path_or_xml) when is_binary(path_or_xml) do
    with {:ok, xml} <- read_xml(path_or_xml),
         {:ok, document} <- parse_xml(xml) do
      build_model(document)
    end
  end

  @spec validate(Model.t()) :: :ok | {:error, term()}
  def validate(%Model{decisions: decisions}) when map_size(decisions) > 0, do: :ok
  def validate(%Model{}), do: {:error, :no_decisions}

  @spec evaluate(Model.t(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  def evaluate(%Model{} = model, decision_name, context \\ %{})
      when is_binary(decision_name) and is_map(context) do
    with :ok <- validate(model),
         {:ok, expression} <- literal_expression(model, decision_name) do
      Arbiter.FEEL.evaluate(expression, context)
    end
  end

  defp read_xml(path_or_xml) do
    if File.exists?(path_or_xml) do
      File.read(path_or_xml)
    else
      {:ok, path_or_xml}
    end
  end

  defp parse_xml(xml) when is_binary(xml) do
    try do
      {doc, _rest} = :xmerl_scan.string(String.to_charlist(xml))
      {:ok, doc}
    rescue
      _ -> {:error, :invalid_xml}
    end
  end

  defp build_model(document) do
    definition_name = xpath_string(document, "/definitions/@name")
    namespace = xpath_string(document, "/definitions/@namespace")

    decisions =
      :xmerl_xpath.string(~c"/definitions/decision", document)
      |> Enum.reduce(%{}, fn node, acc ->
        decision_name = xpath_string(node, "./@name")
        literal_expression = xpath_string(node, "./literalExpression/text")

        if decision_name && literal_expression do
          Map.put(acc, decision_name, literal_expression)
        else
          acc
        end
      end)

    {:ok,
     %Model{
       name: definition_name,
       namespace: namespace,
       decisions: decisions,
       definitions: %{},
       input_data: %{},
       bkms: %{},
       item_definitions: %{}
     }}
  end

  defp literal_expression(%Model{decisions: decisions}, decision_name) do
    case Map.fetch(decisions, decision_name) do
      {:ok, expression} -> {:ok, expression}
      :error -> {:error, {:decision_not_found, decision_name}}
    end
  end

  defp xpath_string(node, path) do
    query = ~c"string(" ++ String.to_charlist(path) ++ ~c")"

    query
    |> :xmerl_xpath.string(node)
    |> normalize_xpath_string()
  end

  defp normalize_xpath_string({:xmlObj, :string, value}) do
    value
    |> to_string()
    |> String.trim()
    |> empty_to_nil()
  end

  defp normalize_xpath_string(value) do
    value
    |> to_string()
    |> String.trim()
    |> empty_to_nil()
  end

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
