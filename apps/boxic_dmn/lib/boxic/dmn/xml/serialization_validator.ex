defmodule Boxic.DMN.XML.SerializationValidator do
  @moduledoc false

  alias Boxic.DMN.Compatibility
  alias Boxic.DMN.Model

  alias Boxic.DMN.Model.{
    ConditionalExpression,
    ContextExpression,
    FilterExpression,
    FunctionDefinition,
    Invocation,
    IteratorExpression,
    ListExpression,
    Relation
  }

  alias Boxic.DMN.SerializationError
  alias Boxic.DMN.Validator

  @allowed_options [:format, :xml_declaration]

  @spec validate(Model.t(), keyword()) :: :ok | {:error, [SerializationError.t()]}
  def validate(%Model{} = model, opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      try do
        errors =
          option_errors(opts) ++
            profile_errors(model) ++
            fidelity_errors(model) ++
            model_validation_errors(model) ++
            import_errors(model) ++
            identifier_errors(model) ++
            identity_errors(model) ++
            unsupported_expression_errors(model)

        case errors do
          [] -> :ok
          errors -> {:error, errors}
        end
      rescue
        _exception -> invalid_model_error()
      catch
        _kind, _reason -> invalid_model_error()
      end
    else
      invalid_options_error()
    end
  end

  def validate(%Model{}, _opts), do: invalid_options_error()

  def validate(model, _opts) do
    {:error,
     [
       error(
         :invalid_model,
         [],
         "Expected a Boxic.DMN.Model.",
         %{type: model_type(model)}
       )
     ]}
  end

  defp invalid_model_error do
    {:error,
     [
       error(
         :invalid_model,
         [],
         "The normalized model could not be inspected safely.",
         nil
       )
     ]}
  end

  defp invalid_options_error do
    {:error,
     [
       error(
         :invalid_option,
         [:options],
         "XML encoding options must be a keyword list.",
         nil
       )
     ]}
  end

  defp option_errors(opts) do
    unknown =
      opts
      |> Keyword.keys()
      |> Enum.reject(&(&1 in @allowed_options))
      |> Enum.uniq()
      |> Enum.map(fn option ->
        error(:invalid_option, [:options, option], "Unknown XML encoding option.", %{
          option: option
        })
      end)

    duplicates =
      opts
      |> Keyword.keys()
      |> Enum.frequencies()
      |> Enum.filter(fn {_option, count} -> count > 1 end)
      |> Enum.map(fn {option, _count} ->
        error(
          :invalid_option,
          [:options, option],
          "XML encoding option was provided more than once.",
          %{option: option}
        )
      end)

    values =
      []
      |> validate_option_value(opts, :format, [:pretty, :compact])
      |> validate_option_value(opts, :xml_declaration, [true, false])

    unknown ++ duplicates ++ values
  end

  defp validate_option_value(errors, opts, option, allowed) do
    case Keyword.fetch(opts, option) do
      :error ->
        errors

      {:ok, value} ->
        if value in allowed do
          errors
        else
          errors ++
            [
              error(
                :invalid_option,
                [:options, option],
                "Invalid XML encoding option value.",
                %{option: option, value: value, allowed: allowed}
              )
            ]
        end
    end
  end

  defp profile_errors(%Model{source_profile: profile}) do
    pinned = Compatibility.pinned_profile().source_profile

    if profile == pinned do
      []
    else
      [
        error(
          :dmn_version_mismatch,
          [:source_profile],
          "The model source DMN profile does not match the pinned output profile.",
          %{source: profile, pinned: pinned}
        )
      ]
    end
  end

  defp fidelity_errors(%Model{serialization_fidelity: :complete}), do: []

  defp fidelity_errors(%Model{serialization_fidelity: {:lossy, losses}}) do
    Enum.with_index(losses, fn loss, index ->
      error(
        :lossy_serialization,
        [:serialization_fidelity, index],
        "The loader did not retain XML content required for a safe round-trip.",
        %{loss: loss}
      )
    end)
  end

  defp fidelity_errors(%Model{serialization_fidelity: other}) do
    [
      error(
        :invalid_model,
        [:serialization_fidelity],
        "The model has invalid serialization fidelity metadata.",
        %{value: other}
      )
    ]
  end

  defp model_validation_errors(model) do
    case Validator.validate(model) do
      :ok ->
        []

      {:error, errors} ->
        Enum.with_index(errors, fn validation_error, index ->
          error(
            :invalid_model,
            [:validation, index],
            "The normalized model is not valid.",
            %{validation_error: validation_error}
          )
        end)
    end
  end

  defp import_errors(model) do
    Enum.flat_map(model.imports, fn {namespace, import} ->
      []
      |> required_import_value(namespace, import, :name)
      |> required_import_value(namespace, import, :namespace)
      |> required_import_value(namespace, import, :import_type)
      |> then(fn errors ->
        if import.namespace == namespace do
          errors
        else
          errors ++
            [
              error(
                :invalid_identifier,
                [:imports, namespace, :namespace],
                "The import map key and embedded namespace do not agree.",
                %{key: namespace, namespace: import.namespace}
              )
            ]
        end
      end)
    end)
  end

  defp required_import_value(errors, namespace, import, field) do
    if is_binary(Map.get(import, field)) do
      errors
    else
      errors ++
        [
          error(
            :missing_required_value,
            [:imports, namespace, field],
            "The import is missing a value required by DMN XML.",
            %{field: field}
          )
        ]
    end
  end

  defp identifier_errors(model) do
    identifiers = collect_identifiers(model, [])

    invalid =
      Enum.flat_map(identifiers, fn {id, path} ->
        if valid_ncname?(id) do
          []
        else
          [
            error(
              :invalid_identifier,
              path,
              "The DMN identifier is not a valid XML NCName.",
              %{id: id}
            )
          ]
        end
      end)

    duplicates =
      identifiers
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.filter(fn {_id, paths} -> length(paths) > 1 end)
      |> Enum.map(fn {id, paths} ->
        error(
          :duplicate_identifier,
          List.first(paths),
          "The DMN identifier occurs more than once in the definitions document.",
          %{id: id, paths: paths}
        )
      end)

    invalid ++ duplicates
  end

  defp collect_identifiers(%_{} = struct, path) do
    own =
      case Map.get(struct, :id) do
        id when is_binary(id) -> [{id, path ++ [:id]}]
        _other -> []
      end

    children =
      struct
      |> Map.from_struct()
      |> Enum.flat_map(fn {key, value} -> collect_identifiers(value, path ++ [key]) end)

    own ++ children
  end

  defp collect_identifiers(map, path) when is_map(map) do
    Enum.flat_map(map, fn {key, value} -> collect_identifiers(value, path ++ [key]) end)
  end

  defp collect_identifiers(list, path) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.flat_map(fn {value, index} -> collect_identifiers(value, path ++ [index]) end)
  end

  defp collect_identifiers(_value, _path), do: []

  defp valid_ncname?(id) do
    :xmerl_lib.is_ncname(String.to_charlist(id))
  rescue
    _error -> false
  end

  defp model_type(%module{}), do: module
  defp model_type(value) when is_map(value), do: :map
  defp model_type(value) when is_list(value), do: :list
  defp model_type(value) when is_binary(value), do: :binary
  defp model_type(value) when is_atom(value), do: :atom
  defp model_type(_value), do: :other

  defp identity_errors(model) do
    [
      {:decisions, model.decisions},
      {:input_data, model.input_data},
      {:bkms, model.bkms},
      {:decision_services, model.decision_services}
    ]
    |> Enum.flat_map(fn {collection_name, collection} ->
      Enum.flat_map(collection, fn {key, value} ->
        if value.id == key do
          []
        else
          [
            error(
              :invalid_identifier,
              [collection_name, key, :id],
              "The map key and embedded DMN identifier do not agree.",
              %{key: key, id: value.id}
            )
          ]
        end
      end)
    end)
  end

  defp unsupported_expression_errors(model) do
    Enum.flat_map(model.decisions, fn {id, decision} ->
      expression_errors(decision.expression, [:decisions, id, :expression])
    end) ++
      Enum.flat_map(model.bkms, fn {id, bkm} ->
        expression_errors(bkm.expression, [:bkms, id, :expression])
      end)
  end

  defp expression_errors({:unsupported, name}, path) do
    [
      error(
        :unsupported_expression,
        path,
        "The expression was not normalized faithfully and cannot be serialized.",
        %{expression: name}
      )
    ]
  end

  defp expression_errors(%ContextExpression{entries: entries}, path) do
    entries
    |> Enum.with_index()
    |> Enum.flat_map(fn {entry, index} ->
      expression_errors(entry.expression, path ++ [:entries, index, :expression])
    end)
  end

  defp expression_errors(%Invocation{} = invocation, path) do
    expression_errors(invocation.function, path ++ [:function]) ++
      (invocation.bindings
       |> Enum.with_index()
       |> Enum.flat_map(fn {binding, index} ->
         expression_errors(binding.expression, path ++ [:bindings, index, :expression])
       end))
  end

  defp expression_errors(%FunctionDefinition{body: body}, path),
    do: expression_errors(body, path ++ [:body])

  defp expression_errors(%Relation{rows: rows}, path) do
    rows
    |> Enum.with_index()
    |> Enum.flat_map(fn {row, row_index} ->
      row
      |> Enum.with_index()
      |> Enum.flat_map(fn {expression, column_index} ->
        expression_errors(expression, path ++ [:rows, row_index, column_index])
      end)
    end)
  end

  defp expression_errors(%ListExpression{items: items}, path) do
    items
    |> Enum.with_index()
    |> Enum.flat_map(fn {item, index} -> expression_errors(item, path ++ [:items, index]) end)
  end

  defp expression_errors(%ConditionalExpression{} = expression, path) do
    expression_errors(expression.condition, path ++ [:condition]) ++
      expression_errors(expression.then_branch, path ++ [:then_branch]) ++
      expression_errors(expression.else_branch, path ++ [:else_branch])
  end

  defp expression_errors(%FilterExpression{} = expression, path) do
    expression_errors(expression.source, path ++ [:source]) ++
      expression_errors(expression.match, path ++ [:match])
  end

  defp expression_errors(%IteratorExpression{} = expression, path) do
    expression_errors(expression.source, path ++ [:source]) ++
      expression_errors(expression.body, path ++ [:body])
  end

  defp expression_errors(_expression, _path), do: []

  defp error(code, path, message, details),
    do: %SerializationError{
      code: code,
      path: bounded(path),
      message: message,
      details: bounded(details)
    }

  defp bounded(value), do: bounded(value, 0)

  defp bounded(value, _depth) when is_binary(value) and byte_size(value) <= 256, do: value

  defp bounded(value, _depth) when is_binary(value),
    do: String.slice(value, 0, 256) <> "…"

  defp bounded(value, depth) when is_list(value) and depth < 4,
    do: value |> Enum.take(20) |> Enum.map(&bounded(&1, depth + 1))

  defp bounded(value, depth) when is_map(value) and depth < 4 do
    value
    |> Enum.take(20)
    |> Map.new(fn {key, item} -> {bounded(key, depth + 1), bounded(item, depth + 1)} end)
  end

  defp bounded(value, depth) when is_tuple(value) and depth < 4 do
    value
    |> Tuple.to_list()
    |> Enum.map(&bounded(&1, depth + 1))
    |> List.to_tuple()
  end

  defp bounded(value, _depth) when is_atom(value) or is_number(value) or is_nil(value), do: value
  defp bounded(_value, _depth), do: :omitted
end
