defmodule Boxic.DMN.XMLWriterSecurityTest do
  use ExUnit.Case, async: false

  alias Boxic.DMN.Model

  alias Boxic.DMN.Model.{
    Decision,
    Definitions,
    ItemComponent,
    ItemDefinition,
    LiteralExpression
  }

  test "escapes markup in attributes and FEEL text without accepting raw fragments" do
    model = base_model()

    model =
      model
      |> put_in([Access.key!(:definitions), Access.key!(:name)], ~s(Model <&> "'"))
      |> put_in(
        [Access.key!(:definitions), Access.key!(:namespace)],
        ~s(urn:example?left="one"&right=<two>)
      )
      |> put_in(
        [Access.key!(:decisions), "decision", Access.key!(:name)],
        ~s(Decision <script attr="x">)
      )
      |> put_in(
        [Access.key!(:decisions), "decision", Access.key!(:expression), Access.key!(:text)],
        ~s("<vendor/>" + "<&>")
      )

    assert {:ok, xml} = Boxic.DMN.encode_xml(model)
    refute xml =~ "<vendor/>"
    refute xml =~ "<script"
    assert xml =~ "&lt;vendor/&gt;"
    assert xml =~ "&lt;script attr=&quot;x&quot;&gt;"

    assert {:ok, reloaded} = Boxic.DMN.load_xml(xml)
    assert reloaded.definitions.name == ~s(Model <&> "'")
    assert reloaded.decisions["decision"].expression.text == ~s("<vendor/>" + "<&>")
  end

  test "encoding caller-provided strings does not grow the atom table" do
    # Load modules and xmerl helpers before taking the baseline.
    assert {:ok, _xml} = Boxic.DMN.encode_xml(base_model())
    before_count = :erlang.system_info(:atom_count)

    for index <- 1..500 do
      model =
        put_in(
          base_model(),
          [Access.key!(:decisions), "decision", Access.key!(:name)],
          "caller-name-#{index}-#{System.unique_integer([:positive])}"
        )

      assert {:ok, _xml} = Boxic.DMN.encode_xml(model)
    end

    assert :erlang.system_info(:atom_count) == before_count
  end

  test "structured error payloads remain bounded for hostile large values" do
    huge = String.duplicate("x", 50_000)

    model = %{
      base_model()
      | source_profile: {:unknown, huge},
        serialization_fidelity: {:lossy, [{:unsupported_xml_element, huge, 100_000}]}
    }

    assert {:error, errors} = Boxic.DMN.encode_xml(model)
    assert errors != []

    assert Enum.all?(errors, fn error ->
             byte_size(inspect(error, limit: :infinity, printable_limit: :infinity)) < 5_000
           end)
  end

  test "deep recursive item definitions encode and reload without changing their shape" do
    depth = 200
    component = nested_component(depth)

    model =
      put_in(
        base_model(),
        [Access.key!(:item_definitions)],
        %{
          "Root" => %ItemDefinition{
            id: "root_item",
            name: "Root",
            components: [component]
          }
        }
      )

    assert {:ok, xml} = Boxic.DMN.encode_xml(model)
    assert {:ok, reloaded} = Boxic.DMN.load_xml(xml)
    assert component_depth(hd(reloaded.item_definitions["Root"].components)) == depth
  end

  test "malformed models and options return structured errors instead of raising" do
    malformed = %Model{definitions: nil, decisions: nil, serialization_fidelity: :complete}

    assert {:error, [%Boxic.DMN.SerializationError{code: :invalid_model}]} =
             Boxic.DMN.encode_xml(malformed)

    assert {:error, [%Boxic.DMN.SerializationError{code: :invalid_option}]} =
             Boxic.DMN.encode_xml(base_model(), [:not_a_keyword])

    assert {:error, [%Boxic.DMN.SerializationError{code: :invalid_option}]} =
             Boxic.DMN.validate_serializable(base_model(), :not_a_list)
  end

  defp base_model do
    %Model{
      definitions: %Definitions{
        id: "definitions",
        name: "Security",
        namespace: "urn:security"
      },
      source_profile: :dmn_1_4,
      serialization_fidelity: :complete,
      decisions: %{
        "decision" => %Decision{
          id: "decision",
          name: "Decision",
          expression: %LiteralExpression{id: "literal", text: "1"}
        }
      }
    }
  end

  defp nested_component(1),
    do: %ItemComponent{id: "component_1", name: "component_1", type_ref: "number"}

  defp nested_component(depth) do
    %ItemComponent{
      id: "component_#{depth}",
      name: "component_#{depth}",
      components: [nested_component(depth - 1)]
    }
  end

  defp component_depth(%ItemComponent{components: []}), do: 1
  defp component_depth(%ItemComponent{components: [child]}), do: 1 + component_depth(child)
end
