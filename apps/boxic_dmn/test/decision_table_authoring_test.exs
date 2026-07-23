defmodule Boxic.DMN.DecisionTableAuthoringTest do
  use ExUnit.Case, async: true

  alias Boxic.DMN.Authoring.DecisionTable, as: Authoring
  alias Boxic.DMN.Model.{DecisionRule, InputClause, OutputClause}

  @model_namespace "https://www.omg.org/spec/DMN/20230324/MODEL/"

  setup do
    xml = """
    <definitions xmlns="#{@model_namespace}" id="defs" name="Table" namespace="urn:table">
      <decision id="decision" name="Decision">
        <decisionTable id="table">
          <input id="input_a"><inputExpression><text>a</text></inputExpression></input>
          <input id="input_b"><inputExpression><text>b</text></inputExpression></input>
          <output id="output_a" name="result"/>
          <rule id="rule_a">
            <inputEntry><text>1</text></inputEntry>
            <inputEntry><text>2</text></inputEntry>
            <outputEntry><text>"a"</text></outputEntry>
          </rule>
          <rule id="rule_b">
            <inputEntry><text>3</text></inputEntry>
            <inputEntry><text>4</text></inputEntry>
            <outputEntry><text>"b"</text></outputEntry>
          </rule>
        </decisionTable>
      </decision>
    </definitions>
    """

    {:ok, model} = Boxic.DMN.load_xml(xml)
    %{model: model}
  end

  test "edits cells by stable IDs", %{model: model} do
    assert {:ok, model} =
             Authoring.put_input_entry(model,
               decision_id: "decision",
               rule_id: "rule_b",
               input_id: "input_a",
               text: ">= 18"
             )

    assert {:ok, model} =
             Authoring.put_output_entry(model,
               decision_id: "decision",
               rule_id: "rule_b",
               output_id: "output_a",
               text: "\"adult\""
             )

    table = model.decisions["decision"].expression
    assert Enum.at(table.rules, 1).input_entries == [">= 18", "4"]
    assert Enum.at(table.rules, 1).output_entries == ["\"adult\""]
  end

  test "adds, moves, and removes clauses while keeping every rule aligned", %{model: model} do
    input = %InputClause{id: "input_c", label: "C", expression: "c", type_ref: "number"}

    assert {:ok, model} =
             Authoring.add_input(model, "decision", input, position: 1, entry_text: "-")

    output = %OutputClause{id: "output_b", name: "reason", type_ref: "string"}

    assert {:ok, model} =
             Authoring.add_output(model, "decision", output,
               position: 0,
               entry_text: "\"unknown\""
             )

    table = model.decisions["decision"].expression
    assert Enum.map(table.inputs, & &1.id) == ["input_a", "input_c", "input_b"]
    assert Enum.map(table.outputs, & &1.id) == ["output_b", "output_a"]
    assert Enum.at(table.rules, 0).input_entries == ["1", "-", "2"]
    assert Enum.at(table.rules, 0).output_entries == ["\"unknown\"", "\"a\""]

    assert {:ok, model} = Authoring.move_input(model, "decision", "input_b", 0)
    assert {:ok, model} = Authoring.move_output(model, "decision", "output_a", 0)
    assert {:ok, model} = Authoring.remove_input(model, "decision", "input_c")
    assert {:ok, model} = Authoring.remove_output(model, "decision", "output_b")

    table = model.decisions["decision"].expression
    assert Enum.map(table.inputs, & &1.id) == ["input_b", "input_a"]
    assert Enum.map(table.outputs, & &1.id) == ["output_a"]
    assert Enum.at(table.rules, 0).input_entries == ["2", "1"]
    assert Enum.at(table.rules, 0).output_entries == ["\"a\""]
    assert :ok = Boxic.DMN.validate(model)
  end

  test "adds and reorders structurally valid rules", %{model: model} do
    rule = %DecisionRule{
      id: "rule_c",
      input_entries: ["5", "6"],
      output_entries: ["\"c\""]
    }

    assert {:ok, model} = Authoring.add_rule(model, "decision", rule, position: 1)
    assert {:ok, model} = Authoring.move_rule(model, "decision", "rule_c", 0)

    assert Enum.map(model.decisions["decision"].expression.rules, & &1.id) ==
             ["rule_c", "rule_a", "rule_b"]

    assert {:ok, model} = Authoring.remove_rule(model, "decision", "rule_a")

    assert Enum.map(model.decisions["decision"].expression.rules, & &1.id) ==
             ["rule_c", "rule_b"]
  end

  test "changes hit policies without permitting invalid aggregation combinations", %{model: model} do
    assert {:ok, model} = Authoring.set_hit_policy(model, "decision", "COLLECT", "COUNT")
    table = model.decisions["decision"].expression
    assert table.hit_policy == "COLLECT"
    assert table.aggregation == "COUNT"

    assert {:error, error} = Authoring.set_hit_policy(model, "decision", "UNIQUE", "SUM")
    assert error.code == :invalid_aggregation
  end

  test "returns structured errors without changing the original model", %{model: model} do
    invalid_rule = %DecisionRule{id: "bad", input_entries: [], output_entries: []}

    assert {:error, error} = Authoring.add_rule(model, "decision", invalid_rule)
    assert error.code == :rule_entry_count_mismatch
    assert length(model.decisions["decision"].expression.rules) == 2

    assert {:error, error} =
             Authoring.put_input_entry(model,
               decision_id: "decision",
               rule_id: "missing",
               input_id: "input_a",
               text: "1"
             )

    assert error.code == :rule_not_found
  end

  test "edited models encode and reload through the public writer", %{model: model} do
    assert {:ok, model} =
             Authoring.put_output_entry(model,
               decision_id: "decision",
               rule_id: "rule_a",
               output_id: "output_a",
               text: "\"edited\""
             )

    assert {:ok, xml} = Boxic.DMN.encode_xml(model)
    assert {:ok, reloaded} = Boxic.DMN.load_xml(xml)

    assert Enum.at(reloaded.decisions["decision"].expression.rules, 0).output_entries ==
             ["\"edited\""]
  end

  test "refuses edits when inspection found unretained XML content", %{model: model} do
    model = %{model | serialization_fidelity: {:lossy, [:documentation]}}

    assert {:error, error} =
             Authoring.put_output_entry(model,
               decision_id: "decision",
               rule_id: "rule_a",
               output_id: "output_a",
               text: "\"unsafe\""
             )

    assert error.code == :unsafe_fidelity
  end
end
