defmodule Boxic.DMN.XMLWriterTest do
  use ExUnit.Case, async: true

  @model_namespace "https://www.omg.org/spec/DMN/20230324/MODEL/"

  test "writes deterministic schema-oriented XML and preserves decision-table semantics" do
    xml = """
    <definitions xmlns="#{@model_namespace}" id="defs" name="Eligibility" namespace="urn:eligibility">
      <inputData id="age" name="Age">
        <variable id="age_variable" name="Age" typeRef="number"/>
      </inputData>
      <decision id="eligibility" name="Eligibility">
        <variable id="eligibility_variable" name="Eligibility" typeRef="string"/>
        <informationRequirement><requiredInput href="#age"/></informationRequirement>
        <decisionTable id="eligibility_table">
          <input id="age_input" label="Age">
            <inputExpression typeRef="number"><text>Age</text></inputExpression>
          </input>
          <output id="result_output" name="result" typeRef="string"/>
          <rule id="adult">
            <inputEntry><text>&gt;= 18</text></inputEntry>
            <outputEntry><text>"adult &amp; eligible"</text></outputEntry>
          </rule>
        </decisionTable>
      </decision>
    </definitions>
    """

    assert {:ok, model} = Boxic.DMN.load_xml(xml)
    assert :ok = Boxic.DMN.validate_serializable(model)
    assert {:ok, written_1} = Boxic.DMN.encode_xml(model)
    assert {:ok, written_2} = Boxic.DMN.encode_xml(model)
    assert written_1 == written_2
    assert written_1 =~ ~s(xmlns="#{@model_namespace}")
    assert written_1 =~ "&gt;= 18"
    assert written_1 =~ "\"adult &amp; eligible\""
    assert String.ends_with?(written_1, "\n")

    assert {:ok, reloaded} = Boxic.DMN.load_xml(written_1)
    assert :ok = Boxic.DMN.validate(reloaded)

    assert {:ok, "adult & eligible"} =
             Boxic.DMN.evaluate(reloaded, "Eligibility", %{"Age" => Decimal.new(20)})

    assert {:ok, written_3} = Boxic.DMN.encode_xml(reloaded)
    assert written_1 == written_3
  end

  test "supports compact output without an XML declaration" do
    assert {:ok, model} =
             Boxic.DMN.load_xml("""
             <definitions xmlns="#{@model_namespace}" id="defs" name="Compact" namespace="urn:compact">
               <decision id="decision" name="Decision">
                 <literalExpression><text>1</text></literalExpression>
               </decision>
             </definitions>
             """)

    assert {:ok, written} =
             Boxic.DMN.encode_xml(model, format: :compact, xml_declaration: false)

    refute written =~ "<?xml"
    refute written =~ "\n"
    assert written =~ "<literalExpression><text>1</text></literalExpression>"
  end

  test "rejects legacy, lossy, invalid, and unsupported models with structured errors" do
    assert {:ok, legacy} =
             Boxic.DMN.inspect_xml("""
             <definitions xmlns="https://www.omg.org/spec/DMN/20191111/MODEL/"
               id="defs" name="Legacy" namespace="urn:legacy">
               <decision id="decision" name="Decision">
                 <literalExpression><text>1</text></literalExpression>
               </decision>
             </definitions>
             """)

    assert {:error, legacy_errors} = Boxic.DMN.encode_xml(legacy)
    assert Enum.any?(legacy_errors, &(&1.code == :dmn_version_mismatch))

    assert {:ok, lossy} =
             Boxic.DMN.load_xml("""
             <definitions xmlns="#{@model_namespace}" id="defs" name="Lossy" namespace="urn:lossy">
               <description>discarded</description>
               <decision id="decision" name="Decision">
                 <literalExpression><text>1</text></literalExpression>
               </decision>
             </definitions>
             """)

    assert {:error, lossy_errors} = Boxic.DMN.encode_xml(lossy)
    assert Enum.any?(lossy_errors, &(&1.code == :lossy_serialization))

    unsupported =
      put_in(
        lossy,
        [
          Access.key!(:serialization_fidelity)
        ],
        :complete
      )
      |> put_in(
        [Access.key!(:decisions), "decision", Access.key!(:expression)],
        {:unsupported, "vendor"}
      )

    assert {:error, unsupported_errors} = Boxic.DMN.encode_xml(unsupported)
    assert Enum.any?(unsupported_errors, &(&1.code == :unsupported_expression))

    assert {:error, option_errors} = Boxic.DMN.encode_xml(unsupported, format: :wide)
    assert Enum.any?(option_errors, &(&1.code == :invalid_option))

    assert {:error, duplicate_option_errors} =
             Boxic.DMN.encode_xml(unsupported, format: :pretty, format: :compact)

    assert Enum.any?(duplicate_option_errors, &(&1.code == :invalid_option))
  end

  test "rejects code points that XML 1.0 cannot encode" do
    assert {:ok, model} =
             Boxic.DMN.load_xml("""
             <definitions xmlns="#{@model_namespace}" id="defs" name="Invalid XML" namespace="urn:invalid">
               <decision id="decision" name="Decision">
                 <literalExpression><text>1</text></literalExpression>
               </decision>
             </definitions>
             """)

    invalid =
      put_in(
        model,
        [Access.key!(:decisions), "decision", Access.key!(:expression), Access.key!(:text)],
        "1\0"
      )

    assert {:error, [error]} = Boxic.DMN.encode_xml(invalid)
    assert error.code == :xml_encoding_failed
  end

  test "round-trips every normalized boxed expression family" do
    assert {:ok, model} =
             Boxic.DMN.load_xml("""
             <definitions xmlns="#{@model_namespace}" id="defs" name="Boxed" namespace="urn:boxed">
               <decision id="context" name="Context">
                 <context id="context_expression">
                   <contextEntry id="named">
                     <variable id="x" name="x" typeRef="number"/>
                     <literalExpression><text>1</text></literalExpression>
                   </contextEntry>
                   <contextEntry id="result">
                     <literalExpression><text>x</text></literalExpression>
                   </contextEntry>
                 </context>
               </decision>
               <decision id="invocation" name="Invocation">
                 <invocation id="invoke">
                   <literalExpression><text>function(a) a</text></literalExpression>
                   <binding>
                     <parameter name="a"/>
                     <literalExpression><text>2</text></literalExpression>
                   </binding>
                 </invocation>
               </decision>
               <decision id="function" name="Function">
                 <functionDefinition id="function_expression">
                   <formalParameter id="parameter" name="a" typeRef="number"/>
                   <literalExpression><text>a + 1</text></literalExpression>
                 </functionDefinition>
               </decision>
               <decision id="relation" name="Relation">
                 <relation id="relation_expression">
                   <column id="column" name="value" typeRef="number"/>
                   <row><literalExpression><text>1</text></literalExpression></row>
                 </relation>
               </decision>
               <decision id="list" name="List">
                 <list id="list_expression">
                   <literalExpression><text>1</text></literalExpression>
                   <literalExpression><text>2</text></literalExpression>
                 </list>
               </decision>
               <decision id="conditional" name="Conditional">
                 <conditional id="conditional_expression">
                   <if><literalExpression><text>true</text></literalExpression></if>
                   <then><literalExpression><text>1</text></literalExpression></then>
                   <else><literalExpression><text>2</text></literalExpression></else>
                 </conditional>
               </decision>
               <decision id="filter" name="Filter">
                 <filter id="filter_expression">
                   <in><literalExpression><text>[1, 2]</text></literalExpression></in>
                   <match><literalExpression><text>item &gt; 1</text></literalExpression></match>
                 </filter>
               </decision>
               <decision id="iterator" name="Iterator">
                 <for id="iterator_expression" iteratorVariable="item">
                   <in><literalExpression><text>[1, 2]</text></literalExpression></in>
                   <return><literalExpression><text>item + 1</text></literalExpression></return>
                 </for>
               </decision>
               <businessKnowledgeModel id="bkm" name="BKM">
                 <variable id="bkm_variable" name="BKM"/>
                 <encapsulatedLogic>
                   <formalParameter id="bkm_parameter" name="value"/>
                   <literalExpression><text>value</text></literalExpression>
                 </encapsulatedLogic>
               </businessKnowledgeModel>
               <decisionService id="service" name="Service">
                 <outputDecision href="#conditional"/>
                 <inputDecision href="#context"/>
               </decisionService>
             </definitions>
             """)

    assert model.serialization_fidelity == :complete
    assert :ok = Boxic.DMN.validate(model)
    assert {:ok, xml} = Boxic.DMN.encode_xml(model)
    assert {:ok, reloaded} = Boxic.DMN.load_xml(xml)
    assert :ok = Boxic.DMN.validate(reloaded)

    assert Map.keys(reloaded.decisions) |> Enum.sort() ==
             Map.keys(model.decisions) |> Enum.sort()

    for id <- Map.keys(model.decisions) do
      assert reloaded.decisions[id].expression == model.decisions[id].expression
    end

    assert reloaded.bkms == model.bkms
    assert reloaded.decision_services == model.decision_services
  end

  test "preflight rejects invalid and duplicate identifiers" do
    assert {:ok, model} =
             Boxic.DMN.inspect_xml("""
             <definitions xmlns="#{@model_namespace}" id="defs" name="Identifiers" namespace="urn:ids">
               <decision id="decision" name="Decision">
                 <decisionTable id="table">
                   <input id="duplicate"><inputExpression><text>value</text></inputExpression></input>
                   <output id="duplicate" name="result"/>
                   <rule id="invalid id">
                     <inputEntry><text>-</text></inputEntry>
                     <outputEntry><text>1</text></outputEntry>
                   </rule>
                 </decisionTable>
               </decision>
             </definitions>
             """)

    assert {:error, errors} = Boxic.DMN.validate_serializable(model)
    assert Enum.any?(errors, &(&1.code == :duplicate_identifier))
    assert Enum.any?(errors, &(&1.code == :invalid_identifier))
  end
end
