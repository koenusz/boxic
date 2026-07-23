defmodule Boxic.DMN.XML.SchemaValidator do
  @moduledoc false

  alias Boxic.DMN.Diagnostic

  @max_xml_bytes 5_000_000
  @max_xml_depth 256
  @max_xml_nodes 100_000
  @max_diagnostic_bytes 4_000
  # xmerl interns XML names as atoms. Keep this list and the extension-name
  # lists below finite so inspection cannot turn attacker-controlled names into
  # an unbounded atom set. The additional prefixes/names are the bounded
  # extension vocabulary exercised by the pinned DMN TCK corpus.
  @safe_prefixes ~w(
    annox dc di dmn dmn11 dmndi drools feel fn include1 include2 jaxb kie
    layout n1 n2 openapi rss semantic tc tns triso trisodmn trisofeed xs xsd
    xsi xsl xml
  )
  @extension_element_names ~w(
    annotate bindings ComponentWidths ComponentsWidthsExtension width
    bendpoints container edge location node sourceAnchor targetAnchor
    component expected inputNode item label labels list modelName resultNode
    testCase testCases value semanticLink any anyAttribute attribute choice
    complexContent complexType element enumeration extension restriction schema
    sequence simpleType annotation documentation import maxInclusive minInclusive
    copy copy-of for-each if output stylesheet template value-of variable
  )
  @extension_attribute_names ~w(
    extensionBindingPrefixes version constraintType constraintsType displayName
    dynamicDecisionService expressionId label logoChoice modelElementRef unparsed
    modelURI points source target uri x y useOutputTypeAsAnswer
    wholeModelService defaultBounds
  )
  @standard_attribute_names ~w(type nil schemaLocation noNamespaceSchemaLocation lang base space id)

  @spec validate_safety(binary()) :: :ok | {:error, [Diagnostic.t()]}
  def validate_safety(xml) when is_binary(xml) do
    cond do
      byte_size(xml) > @max_xml_bytes ->
        {:error,
         [
           diagnostic(
             :xml_size_limit_exceeded,
             "DMN XML exceeds the configured input-size limit.",
             %{actual_bytes: byte_size(xml), maximum_bytes: @max_xml_bytes}
           )
         ]}

      Regex.match?(~r/<!\s*DOCTYPE\b/i, xml) ->
        {:error,
         [
           diagnostic(
             :doctype_forbidden,
             "DTD declarations are not allowed in DMN XML.",
             nil
           )
         ]}

      Regex.match?(~r/<!\s*ENTITY\b/i, xml) ->
        {:error,
         [
           diagnostic(
             :entity_declaration_forbidden,
             "Entity declarations are not allowed in DMN XML.",
             nil
           )
         ]}

      true ->
        :ok
    end
  end

  @doc false
  @spec validate_document(tuple()) :: :ok | {:error, [Diagnostic.t()]}
  def validate_document(document) when is_tuple(document) do
    {nodes, depth} = document_size(document, 1)

    cond do
      depth > @max_xml_depth ->
        {:error,
         [
           diagnostic(
             :xml_depth_limit_exceeded,
             "DMN XML exceeds the configured nesting-depth limit.",
             %{actual_depth: depth, maximum_depth: @max_xml_depth}
           )
         ]}

      nodes > @max_xml_nodes ->
        {:error,
         [
           diagnostic(
             :xml_node_limit_exceeded,
             "DMN XML exceeds the configured node-count limit.",
             %{actual_nodes: nodes, maximum_nodes: @max_xml_nodes}
           )
         ]}

      true ->
        :ok
    end
  end

  @doc false
  @spec validate_inspection_names(binary()) :: :ok | {:error, [Diagnostic.t()]}
  def validate_inspection_names(xml) when is_binary(xml) do
    {element_names, attribute_names} = normative_names()

    event_fun = fn
      {:startElement, _uri, local_name, {prefix, _qualified_name}, attributes}, _location, :ok ->
        with :ok <- safe_prefix(prefix),
             :ok <- safe_name(local_name, element_names, :element),
             :ok <- safe_attributes(attributes, attribute_names) do
          :ok
        end

      _event, _location, state ->
        state
    end

    case :xmerl_sax_parser.stream(xml, event_fun: event_fun, event_state: :ok) do
      {:ok, :ok, _rest} ->
        :ok

      {:ok, {:error, details}, _rest} ->
        unsupported_name_diagnostic(details)

      {:fatal_error, _location, _reason, _end_tags, _state} ->
        {:error,
         [
           diagnostic(
             :invalid_xml,
             "DMN XML is not well formed.",
             nil
           )
         ]}
    end
  catch
    _kind, _reason ->
      {:error, [diagnostic(:invalid_xml, "DMN XML is not well formed.", nil)]}
  end

  @spec validate(binary()) :: :ok | {:error, [Diagnostic.t()]}
  def validate(xml) when is_binary(xml) do
    with :ok <- validate_safety(xml),
         {:ok, executable} <- validator_executable() do
      validate_with_xmllint(executable, xml)
    end
  end

  @spec schema_path() :: Path.t()
  def schema_path do
    Application.app_dir(:boxic_dmn, "priv/schema/dmn-1.5/DMN15.xsd")
  end

  defp validator_executable do
    case System.find_executable("xmllint") do
      nil ->
        {:error,
         [
           diagnostic(
             :schema_validator_unavailable,
             "The DMN XML Schema validator is unavailable.",
             %{required_executable: "xmllint"}
           )
         ]}

      executable ->
        {:ok, executable}
    end
  end

  defp validate_with_xmllint(executable, xml) do
    path =
      Path.join(
        System.tmp_dir!(),
        "boxic-dmn-schema-#{System.unique_integer([:positive, :monotonic])}.xml"
      )

    try do
      {:ok, :ok} =
        File.open(path, [:write, :exclusive], fn io ->
          IO.binwrite(io, xml)
        end)

      case System.cmd(
             executable,
             ["--nonet", "--noout", "--schema", schema_path(), path],
             stderr_to_stdout: true
           ) do
        {_output, 0} ->
          :ok

        {output, _status} ->
          {:error,
           [
             diagnostic(
               :xml_schema_invalid,
               "DMN XML does not conform to the normative DMN 1.5 schema.",
               %{validator_output: truncate(output)}
             )
           ]}
      end
    after
      File.rm(path)
    end
  rescue
    exception ->
      {:error,
       [
         diagnostic(
           :schema_validation_failed,
           "DMN XML schema validation could not be completed.",
           %{exception: exception.__struct__}
         )
       ]}
  end

  defp diagnostic(code, message, details) do
    %Diagnostic{
      code: code,
      category: :xml_schema,
      path: [],
      message: message,
      specification: "DMN 1.5",
      source_profile: :dmn_1_5,
      details: details
    }
  end

  defp truncate(output) do
    if byte_size(output) <= @max_diagnostic_bytes,
      do: output,
      else: binary_part(output, 0, @max_diagnostic_bytes)
  end

  defp document_size(node, depth)
       when is_tuple(node) and tuple_size(node) > 8 and elem(node, 0) == :xmlElement do
    elem(node, 8)
    |> Enum.reduce({1, depth}, fn child, {count, maximum_depth} ->
      {child_count, child_depth} = document_size(child, depth + 1)
      {count + child_count, max(maximum_depth, child_depth)}
    end)
  end

  defp document_size(node, depth) when is_tuple(node), do: {1, depth}
  defp document_size(_node, depth), do: {0, depth}

  defp normative_names do
    schema_directory = Path.dirname(schema_path())

    schema_directory
    |> Path.join("*.xsd")
    |> Path.wildcard()
    |> Enum.reduce({MapSet.new(), MapSet.new()}, fn path, {elements, attributes} ->
      contents = File.read!(path)

      elements =
        Regex.scan(~r/<xsd:element\b[^>]*\bname="([^"]+)"/, contents, capture: :all_but_first)
        |> Enum.reduce(elements, fn [name], names -> MapSet.put(names, name) end)

      attributes =
        Regex.scan(~r/<xsd:attribute\b[^>]*\bname="([^"]+)"/, contents, capture: :all_but_first)
        |> Enum.reduce(attributes, fn [name], names -> MapSet.put(names, name) end)
        |> MapSet.union(MapSet.new(@standard_attribute_names))

      {
        MapSet.union(elements, MapSet.new(@extension_element_names)),
        MapSet.union(attributes, MapSet.new(@extension_attribute_names))
      }
    end)
  end

  defp safe_prefix([]), do: :ok

  defp safe_prefix(prefix) do
    prefix = to_string(prefix)

    if prefix in @safe_prefixes,
      do: :ok,
      else: {:error, %{kind: :namespace_prefix, name: prefix}}
  end

  defp safe_name(name, allowed_names, kind) do
    name = to_string(name)

    if MapSet.member?(allowed_names, name),
      do: :ok,
      else: {:error, %{kind: kind, name: name}}
  end

  defp safe_attributes(attributes, allowed_names) do
    Enum.reduce_while(attributes, :ok, fn
      {_uri, prefix, local_name, _value}, :ok ->
        with :ok <- safe_prefix(prefix),
             :ok <- safe_name(local_name, allowed_names, :attribute) do
          {:cont, :ok}
        else
          {:error, details} -> {:halt, {:error, details}}
        end
    end)
  end

  defp unsupported_name_diagnostic(details) do
    {:error,
     [
       %Diagnostic{
         code: :unsupported_xml_name,
         category: :dmn_model,
         path: [:xml, details.kind, details.name],
         message: "The XML name is outside the bounded normalized-model inspection surface.",
         specification: "DMN 1.5",
         source_profile: :dmn_1_5,
         details: details
       }
     ]}
  end
end
