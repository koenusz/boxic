defmodule Boxic.DMN.TCK.Loader do
  @moduledoc """
  Discovers and normalizes the official vendored DMN TCK test corpus.

  The upstream XML uses a default namespace, so all XPath expressions match
  elements by local name. Invalid test documents become explicit load-error
  cases instead of being raised or silently omitted from corpus totals.
  """

  alias Boxic.DMN.TCK.Case
  alias Boxic.FEEL.Duration
  alias Boxic.FEEL.DateTime, as: FeelDateTime
  alias Boxic.FEEL.Time, as: FeelTime

  @default_root Path.expand("../../../../../../vendor/dmn-tck", __DIR__)
  @test_document_glob "TestCases/**/*-test-*.xml"

  @spec load_all(keyword()) :: [Case.t()]
  def load_all(opts \\ []) do
    root = Keyword.get(opts, :root, @default_root)

    root
    |> Path.join(@test_document_glob)
    |> Path.wildcard()
    |> Enum.flat_map(&parse_case_file(&1, root))
    |> Enum.sort_by(&{&1.group, &1.id, &1.decision_name})
  end

  @spec corpus_stats(keyword()) :: map()
  def corpus_stats(opts \\ []) do
    root = Keyword.get(opts, :root, @default_root)
    cases = load_all(opts)

    missing_models =
      cases
      |> Enum.reject(& &1.load_error)
      |> Enum.map(& &1.model_path)
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&File.regular?/1)
      |> Enum.uniq()

    %{
      test_documents: root |> Path.join(@test_document_glob) |> Path.wildcard() |> length(),
      dmn_models: root |> Path.join("TestCases/**/*.dmn") |> Path.wildcard() |> length(),
      result_entries: length(cases),
      expected_errors: Enum.count(cases, & &1.expect_error),
      load_errors: Enum.count(cases, &(not is_nil(&1.load_error))),
      missing_models: length(missing_models)
    }
  end

  defp parse_case_file(path, root) do
    parse_case_file!(path, root)
  rescue
    exception ->
      [load_error_case(path, root, {:invalid_test_document, Exception.message(exception)})]
  catch
    :exit, reason ->
      [load_error_case(path, root, {:invalid_test_document, reason})]
  end

  defp parse_case_file!(path, root) do
    xml = File.read!(path)
    document = parse_xml!(xml, path)

    model_name =
      xpath_string(document, "/*[local-name()='testCases']/*[local-name()='modelName']/text()")

    if is_nil(model_name) do
      raise "TCK test document has no modelName: #{path}"
    end

    labels =
      xpath(
        document,
        "/*[local-name()='testCases']/*[local-name()='labels']/*[local-name()='label']"
      )
      |> Enum.map(&xpath_string(&1, "./text()"))
      |> Enum.reject(&is_nil/1)

    case_nodes =
      xpath(document, "/*[local-name()='testCases']/*[local-name()='testCase']")

    if case_nodes == [] do
      raise "TCK test document has no testCase elements: #{path}"
    end

    Enum.flat_map(case_nodes, fn case_node ->
      build_cases(case_node, path, root, model_name, labels)
    end)
  end

  defp load_error_case(path, root, reason) do
    %Case{
      group: Path.basename(Path.dirname(path)),
      id: "__load_error__",
      labels: [],
      model_path: nil,
      decision_name: "",
      inputs: %{},
      expected: nil,
      expect_error: false,
      load_error: reason,
      metadata: %{
        case_file: Path.relative_to(path, root),
        compliance_level: compliance_level(path, root),
        root: root
      }
    }
  end

  defp parse_xml!(xml, path) do
    try do
      # xmerl expects the byte sequence declared by the XML prolog. Converting
      # UTF-8 to Unicode codepoints first makes non-ASCII TCK cases invalid.
      {document, _rest} = :xmerl_scan.string(:binary.bin_to_list(xml))
      document
    rescue
      exception ->
        reraise RuntimeError,
                [message: "invalid TCK XML #{path}: #{Exception.message(exception)}"],
                __STACKTRACE__
    end
  end

  defp build_cases(case_node, case_file, root, model_name, labels) do
    group = Path.basename(Path.dirname(case_file))
    upstream_id = xpath_string(case_node, "./@id") || raise("TCK case has no id: #{case_file}")
    result_nodes = xpath(case_node, "./*[local-name()='resultNode']")

    if result_nodes == [] do
      raise "TCK case #{group}/#{upstream_id} has no resultNode"
    end

    inputs =
      xpath(case_node, "./*[local-name()='inputNode']")
      |> Enum.reduce(%{}, fn input_node, acc ->
        name = xpath_string(input_node, "./@name") || raise("TCK inputNode has no name")
        Map.put(acc, name, parse_container(input_node))
      end)

    Enum.map(result_nodes, fn result_node ->
      decision_name =
        xpath_string(result_node, "./@name") || raise("TCK resultNode has no name")

      expect_error = xpath_string(result_node, "./@errorResult") == "true"

      expected_node =
        case xpath(result_node, "./*[local-name()='expected']") do
          [node] -> node
          [] when expect_error -> nil
          [] -> raise "TCK resultNode has no expected value: #{group}/#{upstream_id}"
          _ -> raise "TCK resultNode has multiple expected values: #{group}/#{upstream_id}"
        end

      %Case{
        group: group,
        id: case_id(upstream_id, decision_name, length(result_nodes)),
        labels: labels,
        model_path: Path.expand(model_name, Path.dirname(case_file)),
        decision_name: decision_name,
        inputs: inputs,
        expected: if(expected_node, do: parse_container(expected_node), else: nil),
        expect_error: expect_error,
        metadata: %{
          case_file: Path.relative_to(case_file, root),
          compliance_level: compliance_level(case_file, root),
          description: xpath_string(case_node, "./*[local-name()='description']/text()"),
          model_relative_path: model_name,
          result_type: xpath_string(result_node, "./@type"),
          invocable_name: xpath_string(case_node, "./@invocableName"),
          case_type: xpath_string(case_node, "./@type"),
          root: root,
          upstream_id: upstream_id
        }
      }
    end)
  end

  defp parse_container(node) do
    values = xpath(node, "./*[local-name()='value']")
    lists = xpath(node, "./*[local-name()='list']")
    components = xpath(node, "./*[local-name()='component']")

    case {values, lists, components} do
      {[value], [], []} ->
        parse_value(value)

      {[], [list], []} ->
        parse_list(list)

      {[], [], []} ->
        nil

      {[], [], components} ->
        Map.new(components, &parse_component/1)

      _ ->
        raise "ambiguous TCK value container"
    end
  end

  defp parse_list(node) do
    xpath(node, "./*")
    |> Enum.map(fn child ->
      case local_name(child) do
        "item" -> parse_container(child)
        "value" -> parse_value(child)
        "component" -> child |> parse_component() |> elem(1)
        "list" -> parse_list(child)
        name -> raise "unsupported TCK list element: #{name}"
      end
    end)
  end

  defp parse_component(node) do
    # Empty-string context keys are legal FEEL names and occur in the corpus.
    name = xpath_string_preserve_empty(node, "./@name")
    {name, parse_container(node)}
  end

  defp parse_value(node) do
    type = xpath_string(node, "./@*[local-name()='type']")

    value =
      if type == "xsd:string",
        do: xpath_raw_string(node, "./text()"),
        else: xpath_string(node, "./text()")

    parse_typed_value(value, type)
  end

  defp parse_typed_value(nil, _type), do: nil
  defp parse_typed_value(value, nil), do: value
  defp parse_typed_value(value, "xsd:string"), do: value
  defp parse_typed_value(value, "xsd:boolean"), do: value == "true"
  defp parse_typed_value(value, "xsd:decimal"), do: Decimal.new(value)
  defp parse_typed_value("INF", "xsd:double"), do: :positive_infinity
  defp parse_typed_value("-INF", "xsd:double"), do: :negative_infinity
  defp parse_typed_value("NaN", "xsd:double"), do: :nan
  defp parse_typed_value(value, "xsd:double"), do: Decimal.new(value)
  defp parse_typed_value(value, "xsd:date"), do: parse_date(value)
  defp parse_typed_value(value, "xsd:time"), do: parse_time(value)
  defp parse_typed_value(value, "xsd:dateTime"), do: parse_date_time(value)
  defp parse_typed_value(value, "xsd:duration"), do: parse_duration(value)

  defp parse_typed_value(value, type) do
    raise "unsupported TCK value type #{inspect(type)} for #{inspect(value)}"
  end

  defp parse_date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> value
    end
  end

  defp parse_time(value) do
    case FeelTime.parse(value) do
      {:ok, time} -> time
      _ -> value
    end
  end

  defp parse_date_time(value) do
    case FeelDateTime.parse(value) do
      {:ok, datetime} -> datetime
      _ -> value
    end
  end

  defp parse_duration(value) do
    case Duration.parse_iso8601(value) do
      {:ok, duration} -> duration
      _ -> value
    end
  end

  defp case_id(upstream_id, _decision_name, 1), do: upstream_id
  defp case_id(upstream_id, decision_name, _count), do: "#{upstream_id}/#{decision_name}"

  defp compliance_level(case_file, root) do
    case_file
    |> Path.relative_to(Path.join(root, "TestCases"))
    |> Path.split()
    |> List.first()
  end

  defp local_name({:xmlElement, name, _, _, _, _, _, _, _, _, _, _}) do
    name
    |> to_string()
    |> String.split(":")
    |> List.last()
  end

  defp xpath(node, path) do
    :xmerl_xpath.string(String.to_charlist(path), node)
  end

  defp xpath_string(node, path) do
    query = ~c"string(" ++ String.to_charlist(path) ++ ~c")"

    query
    |> :xmerl_xpath.string(node)
    |> normalize_xpath_string()
  end

  defp xpath_string_preserve_empty(node, path) do
    query = ~c"string(" ++ String.to_charlist(path) ++ ~c")"

    case :xmerl_xpath.string(query, node) do
      {:xmlObj, :string, value} -> value |> to_string() |> String.trim()
      value -> value |> to_string() |> String.trim()
    end
  end

  defp xpath_raw_string(node, path) do
    query = ~c"string(" ++ String.to_charlist(path) ++ ~c")"

    case :xmerl_xpath.string(query, node) do
      {:xmlObj, :string, value} -> to_string(value)
      value -> to_string(value)
    end
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
