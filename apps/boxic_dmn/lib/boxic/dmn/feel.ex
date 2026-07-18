defmodule Boxic.DMN.FEEL do
  @moduledoc false
  def normalize_names(expression, context) do
    context
    |> feel_names()
    |> Enum.filter(fn name ->
      is_binary(name) and not Regex.match?(~r/^[\p{L}_][\p{L}\p{N}_]*$/u, name)
    end)
    |> Enum.uniq()
    |> Enum.sort_by(&String.length/1, :desc)
    |> Enum.with_index()
    |> Enum.reduce({expression, context}, fn {name, index}, {source, bindings} ->
      alias_name = "__dmn_name_#{index}"

      pattern =
        Regex.compile!("(?<![\\p{L}\\p{N}_])#{Regex.escape(name)}(?![\\p{L}\\p{N}_])", "u")

      if Regex.match?(pattern, source) do
        {replace_outside_strings(source, pattern, alias_name),
         alias_feel_name(bindings, name, alias_name)}
      else
        {source, bindings}
      end
    end)
  end

  defp replace_outside_strings(source, pattern, replacement) do
    ~r/("(?:\\.|[^"\\])*")/u
    |> Regex.split(source, include_captures: true)
    |> Enum.map_join(fn segment ->
      if String.starts_with?(segment, "\"") do
        segment
      else
        Regex.replace(pattern, segment, replacement)
      end
    end)
  end

  defp feel_names(map) when is_map(map) and not is_struct(map) do
    Enum.flat_map(map, fn {key, value} -> [key | feel_names(value)] end)
  end

  defp feel_names(list) when is_list(list), do: Enum.flat_map(list, &feel_names/1)
  defp feel_names(_value), do: []

  defp alias_feel_name(map, name, alias_name) when is_map(map) and not is_struct(map) do
    map =
      Map.new(map, fn {key, value} -> {key, alias_feel_name(value, name, alias_name)} end)

    if Map.has_key?(map, name), do: Map.put(map, alias_name, Map.fetch!(map, name)), else: map
  end

  defp alias_feel_name(list, name, alias_name) when is_list(list),
    do: Enum.map(list, &alias_feel_name(&1, name, alias_name))

  defp alias_feel_name(value, _name, _alias_name), do: value
end
