defmodule Arbiter.DMNTest do
  use ExUnit.Case

  alias Arbiter.DMN.Model.Decision
  alias Arbiter.DMN.Model.InputData
  alias Arbiter.DMN.Model.LiteralExpression

  test "loads a namespace-qualified literal decision into normalized structs" do
    xml = """
    <dmn:definitions xmlns:dmn="https://www.omg.org/spec/DMN/20191111/MODEL/"
      id="defs" name="demo" namespace="urn:demo">
      <dmn:inputData id="customer" name="Customer">
        <dmn:variable id="customer_var" name="Customer" typeRef="string"/>
      </dmn:inputData>
      <dmn:decision id="greeting" name="Greeting">
        <dmn:variable id="greeting_var" name="Greeting" typeRef="string"/>
        <dmn:informationRequirement>
          <dmn:requiredInput href="#customer"/>
        </dmn:informationRequirement>
        <dmn:literalExpression id="literal_1">
          <dmn:text>"hello from dmn"</dmn:text>
        </dmn:literalExpression>
      </dmn:decision>
    </dmn:definitions>
    """

    assert {:ok, model} = Arbiter.DMN.load(xml)
    assert model.definitions.id == "defs"
    assert model.definitions.namespace == "urn:demo"
    assert %InputData{name: "Customer"} = model.input_data["customer"]

    assert %Decision{
             name: "Greeting",
             expression: %LiteralExpression{text: "\"hello from dmn\""},
             requirements: [%{kind: :input_data, href: "customer"}]
           } = model.decisions["greeting"]

    assert :ok = Arbiter.DMN.validate(model)
    context = %{"Customer" => "Ada"}
    assert {:ok, "hello from dmn"} = Arbiter.DMN.evaluate(model, "Greeting", context)
    assert {:ok, "hello from dmn"} = Arbiter.DMN.evaluate(model, "greeting", context)
  end

  test "validator reports missing metadata and unresolved references" do
    xml = """
    <definitions id="defs" name="demo">
      <decision id="decision_1">
        <informationRequirement><requiredDecision href="#absent"/></informationRequirement>
        <literalExpression><text>1</text></literalExpression>
      </decision>
    </definitions>
    """

    assert {:ok, model} = Arbiter.DMN.load(xml)
    assert {:error, errors} = Arbiter.DMN.validate(model)
    assert {:missing_attribute, :definitions, :namespace} in errors
    assert {:missing_attribute, {:decision, "decision_1"}, :name} in errors
    assert {:unresolved_reference, "decision_1", :decision, "absent"} in errors
  end

  test "validator rejects malformed decision tables and empty expressions" do
    malformed_table = """
    <definitions id="defs" name="demo" namespace="urn:demo">
      <decision id="table" name="Table"><decisionTable/></decision>
    </definitions>
    """

    assert {:ok, model} = Arbiter.DMN.load(malformed_table)
    assert {:error, errors} = Arbiter.DMN.validate(model)
    assert {:missing_table_component, {:decision_table, "table", :inputs}} in errors
    assert {:missing_table_component, {:decision_table, "table", :outputs}} in errors
    assert {:missing_table_component, {:decision_table, "table", :rules}} in errors

    empty = """
    <definitions id="defs" name="demo" namespace="urn:demo">
      <decision id="empty" name="Empty"><literalExpression><text/></literalExpression></decision>
    </definitions>
    """

    assert {:ok, model} = Arbiter.DMN.load(empty)
    assert {:error, errors} = Arbiter.DMN.validate(model)
    assert {:missing_expression_text, "empty"} in errors
  end

  test "loader rejects malformed XML, non-definitions roots, and duplicate IDs" do
    assert {:error, :invalid_xml} = Arbiter.DMN.load("<definitions>")
    assert {:error, :invalid_definitions_document} = Arbiter.DMN.load("<decision/>")

    duplicates = """
    <definitions id="defs" name="demo" namespace="urn:demo">
      <decision id="same" name="One"><literalExpression><text>1</text></literalExpression></decision>
      <decision id="same" name="Two"><literalExpression><text>2</text></literalExpression></decision>
    </definitions>
    """

    assert {:ok, model} = Arbiter.DMN.load(duplicates)
    assert {:error, errors} = Arbiter.DMN.validate(model)
    assert {:duplicate_id, "same"} in errors
  end

  test "evaluates literal decision dependencies and injects input data by DMN name" do
    xml = """
    <definitions id="defs" name="dependency model" namespace="urn:dependencies">
      <inputData id="input_amount" name="Amount">
        <variable name="Amount" typeRef="number"/>
      </inputData>
      <decision id="base" name="Base">
        <informationRequirement><requiredInput href="#input_amount"/></informationRequirement>
        <literalExpression><text>Amount * 2</text></literalExpression>
      </decision>
      <decision id="total" name="Total">
        <informationRequirement><requiredDecision href="#base"/></informationRequirement>
        <literalExpression><text>Base + 1</text></literalExpression>
      </decision>
    </definitions>
    """

    assert {:ok, model} = Arbiter.DMN.load(xml)
    assert :ok = Arbiter.DMN.validate(model)

    assert {:ok, %Decimal{} = result} =
             Arbiter.DMN.evaluate(model, "Total", %{"Amount" => Decimal.new("20")})

    assert Decimal.equal?(result, Decimal.new("41"))
    assert {:error, {:missing_input, "Amount"}} = Arbiter.DMN.evaluate(model, "Total")
  end

  test "detects cyclic decision dependencies during execution" do
    xml = """
    <definitions id="defs" name="cycle" namespace="urn:cycle">
      <decision id="a" name="A">
        <informationRequirement><requiredDecision href="#b"/></informationRequirement>
        <literalExpression><text>B</text></literalExpression>
      </decision>
      <decision id="b" name="B">
        <informationRequirement><requiredDecision href="#a"/></informationRequirement>
        <literalExpression><text>A</text></literalExpression>
      </decision>
    </definitions>
    """

    assert {:ok, model} = Arbiter.DMN.load(xml)
    assert :ok = Arbiter.DMN.validate(model)
    assert {:error, {:cyclic_decision_dependency, "a"}} = Arbiter.DMN.evaluate(model, "A")
  end

  test "parses and evaluates a unique decision table with multiple outputs and defaults" do
    xml = """
    <definitions id="defs" name="table" namespace="urn:table">
      <inputData id="age" name="Age"><variable name="Age" typeRef="number"/></inputData>
      <decision id="category" name="Category">
        <informationRequirement><requiredInput href="#age"/></informationRequirement>
        <decisionTable hitPolicy="UNIQUE">
          <input><inputExpression typeRef="number"><text>Age</text></inputExpression></input>
          <output name="label" typeRef="string"><defaultOutputEntry><text>"unknown"</text></defaultOutputEntry></output>
          <output name="adult" typeRef="boolean"><defaultOutputEntry><text>false</text></defaultOutputEntry></output>
          <rule id="adult_rule">
            <inputEntry><text>&gt;= 18</text></inputEntry>
            <outputEntry><text>"adult"</text></outputEntry>
            <outputEntry><text>true</text></outputEntry>
          </rule>
          <rule id="child_rule">
            <inputEntry><text>&lt; 18</text></inputEntry>
            <outputEntry><text>"child"</text></outputEntry>
            <outputEntry><text>false</text></outputEntry>
          </rule>
        </decisionTable>
      </decision>
    </definitions>
    """

    assert {:ok, model} = Arbiter.DMN.load(xml)
    assert :ok = Arbiter.DMN.validate(model)

    assert {:ok, %{"label" => "adult", "adult" => true}} =
             Arbiter.DMN.evaluate(model, "Category", %{"Age" => Decimal.new(20)})

    assert {:ok, %{"label" => "child", "adult" => false}} =
             Arbiter.DMN.evaluate(model, "Category", %{"Age" => Decimal.new(10)})
  end

  test "decision-table validation catches malformed rules and unsupported policies" do
    xml = """
    <definitions id="defs" name="invalid table" namespace="urn:table">
      <decision id="invalid" name="Invalid">
        <decisionTable hitPolicy="CUSTOM">
          <input><inputExpression><text>value</text></inputExpression></input>
          <output name="result"/>
          <rule id="bad"><outputEntry><text>1</text></outputEntry></rule>
        </decisionTable>
      </decision>
    </definitions>
    """

    assert {:ok, model} = Arbiter.DMN.load(xml)
    assert {:error, errors} = Arbiter.DMN.validate(model)
    assert {:unsupported_hit_policy, "invalid", "CUSTOM"} in errors
    assert {:entry_count_mismatch, "bad", :input_entries, 1, 0} in errors
  end

  test "collect max aggregates all matching numeric outputs" do
    xml = """
    <definitions id="defs" name="collect max" namespace="urn:table">
      <inputData id="score" name="Score"><variable name="Score" typeRef="number"/></inputData>
      <decision id="maximum" name="Maximum">
        <informationRequirement><requiredInput href="#score"/></informationRequirement>
        <decisionTable hitPolicy="COLLECT" aggregation="MAX">
          <input><inputExpression><text>Score</text></inputExpression></input>
          <output name="result" typeRef="number"/>
          <rule id="one"><inputEntry><text>&gt; 0</text></inputEntry><outputEntry><text>10</text></outputEntry></rule>
          <rule id="two"><inputEntry><text>&gt; 5</text></inputEntry><outputEntry><text>20</text></outputEntry></rule>
        </decisionTable>
      </decision>
    </definitions>
    """

    assert {:ok, model} = Arbiter.DMN.load(xml)
    assert :ok = Arbiter.DMN.validate(model)

    assert {:ok, %Decimal{} = result} =
             Arbiter.DMN.evaluate(model, "Maximum", %{"Score" => Decimal.new(8)})

    assert Decimal.equal?(result, Decimal.new(20))
  end

  test "evaluation coerces legacy lexical inputs and normalizes punctuation in FEEL names" do
    xml = """
    <definitions id="defs" name="legacy inputs" namespace="urn:legacy">
      <inputData id="amount" name="Requested-Amount">
        <variable name="Requested-Amount" typeRef="number"/>
      </inputData>
      <decision id="double" name="Double">
        <variable name="Double" typeRef="number"/>
        <literalExpression><text>Requested-Amount * 2</text></literalExpression>
      </decision>
    </definitions>
    """

    assert {:ok, model} = Arbiter.DMN.load(xml)
    assert {:ok, result} = Arbiter.DMN.evaluate(model, "Double", %{"Requested-Amount" => "21"})
    assert Decimal.equal?(result, Decimal.new(42))
  end
end
