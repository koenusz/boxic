defmodule Boxic.DMN.CompatibilityAndFidelityTest do
  use ExUnit.Case, async: true

  alias Boxic.DMN.Compatibility
  alias Boxic.DMN.Model.LiteralExpression

  test "publishes the pinned DMN 1.4 compatibility profile" do
    assert %{
             version: "1.4",
             source_profile: :dmn_1_4,
             model_namespace: "https://www.omg.org/spec/DMN/20211108/MODEL/",
             schema: "DMN14.xsd",
             tck_revision: "0dbcaf9b98bc3af4e36d44a7aed95e9e85703a13"
           } = Compatibility.pinned_profile()
  end

  test "records the source DMN profile without rejecting legacy documents" do
    assert {:ok, current} =
             Boxic.DMN.load_xml("""
             <definitions xmlns="https://www.omg.org/spec/DMN/20211108/MODEL/"
               id="defs" name="Current" namespace="urn:current">
               <decision id="decision" name="Decision">
                 <literalExpression><text>1</text></literalExpression>
               </decision>
             </definitions>
             """)

    assert current.source_profile == :dmn_1_4

    assert {:ok, legacy} =
             Boxic.DMN.load_xml("""
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
             Boxic.DMN.load_xml("""
             <definitions xmlns="https://www.omg.org/spec/DMN/20211108/MODEL/"
               id="defs" name="Authored" namespace="urn:authored">
               <description>Important documentation</description>
               <decision id="decision" name="Decision">
                 <literalExpression><text>1</text></literalExpression>
               </decision>
               <dmndi:DMNDI xmlns:dmndi="https://www.omg.org/spec/DMN/20191111/DMNDI/"/>
             </definitions>
             """)

    assert {:lossy, losses} = model.serialization_fidelity
    assert {:discarded_xml_content, "description", 1} in losses
    assert {:discarded_xml_content, "DMNDI layout", 1} in losses
  end

  test "marks unknown elements as lossy instead of silently dropping them" do
    assert {:ok, model} =
             Boxic.DMN.load_xml("""
             <definitions xmlns="https://www.omg.org/spec/DMN/20211108/MODEL/"
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

  test "marks standard and vendor attributes that the normalized model does not retain" do
    assert {:ok, model} =
             Boxic.DMN.load_xml("""
             <definitions xmlns="https://www.omg.org/spec/DMN/20211108/MODEL/"
               xmlns:vendor="urn:vendor" id="defs" name="Attributes"
               namespace="urn:attributes" exporter="Example">
               <decision id="decision" name="Decision" vendor:color="blue">
                 <literalExpression><text>1</text></literalExpression>
               </decision>
             </definitions>
             """)

    assert {:lossy, losses} = model.serialization_fidelity
    assert {:discarded_xml_attribute, "definitions", "exporter", 1} in losses
    assert {:discarded_xml_attribute, "decision", "{urn:vendor}color", 1} in losses
  end

  test "preserves significant FEEL text whitespace" do
    assert {:ok, model} =
             Boxic.DMN.load_xml("""
             <definitions xmlns="https://www.omg.org/spec/DMN/20211108/MODEL/"
               id="defs" name="Whitespace" namespace="urn:whitespace">
               <decision id="decision" name="Decision">
                 <literalExpression><text>  "kept"  </text></literalExpression>
               </decision>
             </definitions>
             """)

    assert %LiteralExpression{text: "  \"kept\"  "} = model.decisions["decision"].expression
    assert model.serialization_fidelity == :complete
  end
end
