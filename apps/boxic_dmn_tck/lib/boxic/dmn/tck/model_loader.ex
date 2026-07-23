defmodule Boxic.DMN.TCK.ModelLoader do
  @moduledoc false

  def load(model_path) do
    with {:ok, xml} <- File.read(model_path) do
      Boxic.DMN.load_xml(xml, imports: sibling_models(model_path))
    end
  end

  defp sibling_models(model_path) do
    model_path
    |> Path.dirname()
    |> Path.join("*.dmn")
    |> Path.wildcard()
    |> Enum.reject(&(&1 == model_path))
    |> Enum.reduce(%{}, fn candidate_path, candidates ->
      with {:ok, candidate_xml} <- File.read(candidate_path),
           {:ok, candidate} <- Boxic.DMN.inspect_xml(candidate_xml),
           namespace when is_binary(namespace) <- candidate.definitions.namespace do
        Map.put(candidates, namespace, candidate_xml)
      else
        _error -> candidates
      end
    end)
  end
end
