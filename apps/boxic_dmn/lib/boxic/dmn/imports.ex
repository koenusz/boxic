defmodule Boxic.DMN.Imports do
  @moduledoc false
  alias Boxic.DMN.Model

  def merge(%Model{} = model, candidates) do
    merge_imported_models(model, imported_closure(model, candidates))
  end

  defp merge_imported_models(model, imported_models) do
    Enum.reduce(imported_models, model, fn imported, %Model{} = result ->
      namespace = imported.definitions.namespace

      %Model{
        result
        | imports: Map.merge(result.imports, imported.imports),
          decisions:
            merge_qualified(result.decisions, imported.decisions, namespace, &qualify_node/2),
          input_data:
            merge_qualified(result.input_data, imported.input_data, namespace, fn node, _ ->
              node
            end),
          bkms: merge_qualified(result.bkms, imported.bkms, namespace, &qualify_node/2),
          item_definitions:
            merge_qualified(
              result.item_definitions,
              imported.item_definitions,
              namespace,
              fn node, _ -> node end
            ),
          decision_services:
            merge_qualified(
              result.decision_services,
              imported.decision_services,
              namespace,
              fn node, _ -> node end
            ),
          issues: result.issues ++ imported.issues
      }
    end)
  end

  defp imported_closure(model, candidates) do
    available = Map.new(candidates, &{&1.definitions.namespace, &1})
    collect_imports(Map.keys(model.imports), available, %{}, [])
  end

  defp collect_imports([], _available, _seen, result), do: Enum.reverse(result)

  defp collect_imports([namespace | rest], available, seen, result) do
    if Map.has_key?(seen, namespace) do
      collect_imports(rest, available, seen, result)
    else
      seen = Map.put(seen, namespace, true)

      case Map.get(available, namespace) do
        nil ->
          collect_imports(rest, available, seen, result)

        imported ->
          collect_imports(
            Map.keys(imported.imports) ++ rest,
            available,
            seen,
            [imported | result]
          )
      end
    end
  end

  defp merge_qualified(target, source, namespace, transform) do
    Enum.reduce(source, target, fn {id, node}, result ->
      Map.put(result, namespace <> "#" <> id, transform.(node, namespace))
    end)
  end

  defp qualify_node(%{requirements: requirements} = node, namespace) do
    qualified =
      Enum.map(requirements, fn requirement ->
        if is_binary(requirement.href) and not String.contains?(requirement.href, "#") do
          %{requirement | href: namespace <> "#" <> requirement.href}
        else
          requirement
        end
      end)

    %{node | requirements: qualified}
  end
end
