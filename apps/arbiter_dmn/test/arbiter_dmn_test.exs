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
    assert {:ok, "hello from dmn"} = Arbiter.DMN.evaluate(model, "Greeting", %{})
    assert {:ok, "hello from dmn"} = Arbiter.DMN.evaluate(model, "greeting", %{})
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

  test "validator rejects unsupported and empty expressions" do
    unsupported = """
    <definitions id="defs" name="demo" namespace="urn:demo">
      <decision id="table" name="Table"><decisionTable/></decision>
    </definitions>
    """

    assert {:ok, model} = Arbiter.DMN.load(unsupported)
    assert {:error, errors} = Arbiter.DMN.validate(model)
    assert {:unsupported_expression, "table", "decisionTable"} in errors

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
end
