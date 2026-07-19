defmodule Boxic.DMN.XMLWriterGeneratedTest do
  use ExUnit.Case, async: true

  alias Boxic.DMN.Model

  alias Boxic.DMN.Model.{
    Decision,
    DecisionRule,
    DecisionTable,
    Definitions,
    InputClause,
    OutputClause
  }

  @policies [
    {"UNIQUE", nil},
    {"FIRST", nil},
    {"ANY", nil},
    {"PRIORITY", nil},
    {"RULE_ORDER", nil},
    {"OUTPUT_ORDER", nil},
    {"COLLECT", nil},
    {"COLLECT", "SUM"},
    {"COLLECT", "MIN"},
    {"COLLECT", "MAX"},
    {"COLLECT", "COUNT"}
  ]

  test "deterministically generated valid tables round-trip and become byte-idempotent" do
    for {policy, aggregation} <- @policies,
        rule_count <- [1, 3, 12] do
      model = generated_model(policy, aggregation, rule_count)

      assert :ok = Boxic.DMN.validate(model)
      assert {:ok, first_xml} = Boxic.DMN.encode_xml(model)
      assert {:ok, reloaded} = Boxic.DMN.load_xml(first_xml)
      assert :ok = Boxic.DMN.validate(reloaded)
      assert {:ok, second_xml} = Boxic.DMN.encode_xml(reloaded)
      assert first_xml == second_xml

      first_table = model.decisions["decision"].expression
      second_table = reloaded.decisions["decision"].expression
      assert second_table == first_table
    end
  end

  test "generated invalid row arities return structured errors and never raise" do
    for input_count <- 0..3,
        output_count <- 0..2 do
      model = generated_model("UNIQUE", nil, 1)

      model =
        update_in(
          model.decisions["decision"].expression.rules,
          fn [rule] ->
            [
              %{
                rule
                | input_entries: List.duplicate("-", input_count),
                  output_entries: List.duplicate("1", output_count)
              }
            ]
          end
        )

      if input_count == 2 and output_count == 1 do
        assert {:ok, _xml} = Boxic.DMN.encode_xml(model)
      else
        assert {:error, errors} = Boxic.DMN.encode_xml(model)
        assert errors != []
        assert Enum.all?(errors, &match?(%Boxic.DMN.SerializationError{}, &1))
      end
    end
  end

  defp generated_model(policy, aggregation, rule_count) do
    inputs = [
      %InputClause{id: "input_a", label: "A", expression: "a", type_ref: "number"},
      %InputClause{id: "input_b", label: "B", expression: "b", type_ref: "number"}
    ]

    outputs = [
      %OutputClause{
        id: "output",
        name: "result",
        type_ref: "number",
        allowed_values: "1, 2, 3",
        default_output: "0"
      }
    ]

    rules =
      for index <- 1..rule_count do
        %DecisionRule{
          id: "rule_#{index}",
          input_entries: [Integer.to_string(index), "-"],
          output_entries: [Integer.to_string(index)]
        }
      end

    table = %DecisionTable{
      id: "table",
      hit_policy: policy,
      aggregation: aggregation,
      inputs: inputs,
      outputs: outputs,
      rules: rules
    }

    %Model{
      definitions: %Definitions{
        id: "definitions",
        name: "Generated #{policy}",
        namespace: "urn:generated:#{String.downcase(policy)}"
      },
      source_profile: :dmn_1_4,
      serialization_fidelity: :complete,
      decisions: %{
        "decision" => %Decision{id: "decision", name: "Decision", expression: table}
      }
    }
  end
end
