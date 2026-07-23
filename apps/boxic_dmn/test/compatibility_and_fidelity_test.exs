defmodule Boxic.DMN.CompatibilityAndFidelityTest do
  use ExUnit.Case, async: true

  alias Boxic.DMN.Compatibility
  alias Boxic.DMN.Model.LiteralExpression

  test "publishes the pinned DMN 1.5 compatibility profile" do
    assert %{
             version: "1.5",
             source_profile: :dmn_1_5,
             model_namespace: "https://www.omg.org/spec/DMN/20230324/MODEL/",
             feel_namespace: "https://www.omg.org/spec/DMN/20230324/FEEL/",
             schema: "DMN15.xsd",
             tck_revision: "a162739daee85fb28e9d3bec2f306505992dae0f"
           } = Compatibility.pinned_profile()
  end

  test "records the source DMN profile without rejecting legacy documents" do
    assert {:ok, current} =
             Boxic.DMN.inspect_xml("""
             <definitions xmlns="https://www.omg.org/spec/DMN/20230324/MODEL/"
               id="defs" name="Current" namespace="urn:current">
               <decision id="decision" name="Decision">
                 <literalExpression><text>1</text></literalExpression>
               </decision>
             </definitions>
             """)

    assert current.source_profile == :dmn_1_5

    assert {:ok, legacy} =
             Boxic.DMN.inspect_xml("""
             <definitions xmlns="https://www.omg.org/spec/DMN/20191111/MODEL/"
               id="defs" name="Legacy" namespace="urn:legacy">
               <decision id="decision" name="Decision">
                 <literalExpression><text>1</text></literalExpression>
               </decision>
             </definitions>
             """)

    assert legacy.source_profile == :dmn_1_3
  end

  test "marks discarded authored content as lossy for serialization" do
    assert {:ok, model} =
             Boxic.DMN.inspect_xml("""
             <definitions xmlns="https://www.omg.org/spec/DMN/20230324/MODEL/"
               id="defs" name="Authored" namespace="urn:authored">
               <description>Important documentation</description>
               <decision id="decision" name="Decision">
                 <literalExpression><text>1</text></literalExpression>
               </decision>
               <dmndi:DMNDI xmlns:dmndi="https://www.omg.org/spec/DMN/20230324/DMNDI/"/>
             </definitions>
             """)

    assert {:lossy, losses} = model.serialization_fidelity
    assert {:discarded_xml_content, "description", 1} in losses
    assert {:discarded_xml_content, "DMNDI layout", 1} in losses
  end

  test "marks unknown elements as lossy instead of silently dropping them" do
    assert {:ok, model} =
             Boxic.DMN.inspect_xml("""
             <definitions xmlns="https://www.omg.org/spec/DMN/20230324/MODEL/"
               id="defs" name="Unknown" namespace="urn:unknown">
               <artifact id="unsupported"/>
               <decision id="decision" name="Decision">
                 <literalExpression><text>1</text></literalExpression>
               </decision>
             </definitions>
             """)

    assert {:lossy, losses} = model.serialization_fidelity
    assert {:unsupported_xml_element, "artifact", 1} in losses
  end

  test "marks standard attributes as lossy and rejects unbounded vendor names safely" do
    assert {:ok, model} =
             Boxic.DMN.inspect_xml("""
             <definitions xmlns="https://www.omg.org/spec/DMN/20230324/MODEL/"
               id="defs" name="Attributes"
               namespace="urn:attributes" exporter="Example">
               <decision id="decision" name="Decision">
                 <literalExpression><text>1</text></literalExpression>
               </decision>
             </definitions>
             """)

    assert {:lossy, losses} = model.serialization_fidelity
    assert {:discarded_xml_attribute, "definitions", "exporter", 1} in losses

    assert {:error, [diagnostic]} =
             Boxic.DMN.inspect_xml("""
             <definitions xmlns="https://www.omg.org/spec/DMN/20230324/MODEL/"
               xmlns:vendor="urn:vendor" id="defs" name="Vendor" namespace="urn:vendor-test">
               <decision id="decision" name="Decision" vendor:color="blue">
                 <literalExpression><text>1</text></literalExpression>
               </decision>
             </definitions>
             """)

    assert diagnostic.code == :unsupported_xml_name
  end

  test "preserves significant FEEL text whitespace" do
    assert {:ok, model} =
             Boxic.DMN.load_xml("""
             <definitions xmlns="https://www.omg.org/spec/DMN/20230324/MODEL/"
               id="defs" name="Whitespace" namespace="urn:whitespace">
               <decision id="decision" name="Decision">
                 <literalExpression><text>  "kept"  </text></literalExpression>
               </decision>
             </definitions>
             """)

    assert %LiteralExpression{text: "  \"kept\"  "} = model.decisions["decision"].expression
    assert model.serialization_fidelity == :complete
  end

  test "resolves the DMN 1.5 FEEL default and declaration precedence" do
    feel = "https://www.omg.org/spec/DMN/20230324/FEEL/"

    assert {:ok, ^feel} = Compatibility.expression_language(:dmn_1_5, nil, nil)
    assert {:ok, ^feel} = Compatibility.expression_language(:dmn_1_5, feel, nil)
    assert {:ok, ^feel} = Compatibility.expression_language(:dmn_1_5, "other", feel)

    assert {:error, {:unsupported_expression_language, "other"}} =
             Compatibility.expression_language(:dmn_1_5, "other", nil)
  end

  test "diagnostics have a persistence-safe public representation" do
    diagnostic = %Boxic.DMN.Diagnostic{
      code: :unsupported_expression_language,
      category: :executable_profile,
      path: [:decisions, "decision", :expression],
      message: "Expression language is not executable.",
      specification: "DMN 1.5",
      source_profile: :dmn_1_5,
      details: %{language: "other"}
    }

    assert %{
             "code" => "unsupported_expression_language",
             "category" => "executable_profile",
             "path" => ["decisions", "decision", "expression"],
             "source_profile" => "dmn_1_5",
             "details" => %{"language" => "other"}
           } = Boxic.DMN.Diagnostic.to_map(diagnostic)
  end
end
