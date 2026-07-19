defmodule Boxic.DMN.XML.Emitter do
  @moduledoc false

  alias Boxic.DMN.XML.Element

  @spec emit(Element.t(), keyword()) :: iodata()
  def emit(%Element{} = root, opts) do
    format = Keyword.fetch!(opts, :format)
    declaration = Keyword.fetch!(opts, :xml_declaration)

    body =
      case format do
        :compact -> compact(root)
        :pretty -> [pretty(root, 0), "\n"]
      end

    if declaration do
      ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>", declaration_separator(format), body]
    else
      body
    end
  end

  defp declaration_separator(:pretty), do: "\n"
  defp declaration_separator(:compact), do: ""

  defp compact(%Element{name: name, attrs: attrs, children: []}),
    do: ["<", name, attributes(attrs), "/>"]

  defp compact(%Element{name: name, attrs: attrs, children: children}) do
    ["<", name, attributes(attrs), ">", Enum.map(children, &compact_child/1), "</", name, ">"]
  end

  defp compact_child(%Element{} = element), do: compact(element)
  defp compact_child({:text, value}), do: escape_text(value)

  defp pretty(%Element{name: name, attrs: attrs, children: []}, depth),
    do: [indent(depth), "<", name, attributes(attrs), "/>"]

  defp pretty(%Element{name: name, attrs: attrs, children: [{:text, value}]}, depth) do
    [indent(depth), "<", name, attributes(attrs), ">", escape_text(value), "</", name, ">"]
  end

  defp pretty(%Element{name: name, attrs: attrs, children: children}, depth) do
    [
      indent(depth),
      "<",
      name,
      attributes(attrs),
      ">\n",
      children
      |> Enum.map(&pretty_child(&1, depth + 1))
      |> Enum.intersperse("\n"),
      "\n",
      indent(depth),
      "</",
      name,
      ">"
    ]
  end

  defp pretty_child(%Element{} = element, depth), do: pretty(element, depth)
  defp pretty_child({:text, value}, depth), do: [indent(depth), escape_text(value)]

  defp attributes(attrs) do
    Enum.map(attrs, fn {name, value} ->
      [" ", name, "=\"", escape_attribute(value), "\""]
    end)
  end

  defp escape_text(value) do
    validate_xml_string!(value)

    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp escape_attribute(value) do
    value
    |> escape_text()
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp indent(depth), do: :binary.copy("  ", depth)

  defp validate_xml_string!(value) when is_binary(value) do
    valid_codepoints? =
      String.valid?(value) and
        value
        |> String.to_charlist()
        |> Enum.all?(fn codepoint ->
          codepoint in [0x9, 0xA, 0xD] or
            codepoint in 0x20..0xD7FF or
            codepoint in 0xE000..0xFFFD or
            codepoint in 0x10000..0x10FFFF
        end)

    if not valid_codepoints?, do: raise(ArgumentError, "value contains invalid XML code points")
  end
end
