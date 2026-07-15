defmodule Arbiter.DMN.TCK.Loader do
  @moduledoc """
  Discovers and loads vendored TCK test cases.
  """

  alias Arbiter.DMN.TCK.Case

  @default_root Path.expand("../../../../../../vendor/dmn-tck", __DIR__)

  @spec load_all(keyword()) :: [Case.t()]
  def load_all(opts \\ []) do
    root = Keyword.get(opts, :root, @default_root)

    root
    |> Path.join("**/*.test.xml")
    |> Path.wildcard()
    |> Enum.flat_map(&parse_case_file(&1, root))
    |> Enum.sort_by(&{&1.group, &1.id})
  end

  defp parse_case_file(path, root) do
    with {:ok, xml} <- File.read(path),
         {:ok, document} <- parse_xml(xml),
         case_nodes when is_list(case_nodes) <-
           :xmerl_xpath.string(~c"/testCases/testCase", document) do
      Enum.map(case_nodes, fn case_node -> build_case(case_node, path, root) end)
    else
      _ -> []
    end
  end

  defp parse_xml(xml) do
    try do
      {doc, _rest} = :xmerl_scan.string(String.to_charlist(xml))
      {:ok, doc}
    rescue
      _ -> {:error, :invalid_xml}
    end
  end

  defp build_case(case_node, case_file, root) do
    group = xpath_string(case_node, "./@group") || Path.basename(Path.dirname(case_file))
    id = xpath_string(case_node, "./@id") || "unknown"

    labels =
      :xmerl_xpath.string(~c"./labels/label", case_node)
      |> Enum.map(fn label_node -> xpath_string(label_node, "./text()") end)
      |> Enum.reject(&is_nil/1)

    model_relative = xpath_string(case_node, "./model/text()")
    decision_name = xpath_string(case_node, "./decision/text()")

    expected =
      parse_typed_value(
        xpath_string(case_node, "./expected/text()"),
        xpath_string(case_node, "./expected/@type")
      )

    inputs =
      :xmerl_xpath.string(~c"./inputs/input", case_node)
      |> Enum.reduce(%{}, fn input_node, acc ->
        name = xpath_string(input_node, "./@name")
        value_type = xpath_string(input_node, "./@type") || "string"
        value = parse_typed_value(xpath_string(input_node, "./text()"), value_type)

        if name, do: Map.put(acc, name, value), else: acc
      end)

    %Case{
      group: group,
      id: id,
      labels: labels,
      model_path: Path.expand(model_relative || "", Path.dirname(case_file)),
      decision_name: decision_name || "",
      inputs: inputs,
      expected: expected,
      metadata: %{
        case_file: Path.relative_to(case_file, root),
        model_relative_path: model_relative,
        root: root
      }
    }
  end

  defp parse_typed_value(nil, _type), do: nil
  defp parse_typed_value(value, "string"), do: value
  defp parse_typed_value("null", _type), do: nil
  defp parse_typed_value(value, "boolean"), do: value == "true"
  defp parse_typed_value(value, "number"), do: Decimal.new(value)
  defp parse_typed_value(value, _type), do: value

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
