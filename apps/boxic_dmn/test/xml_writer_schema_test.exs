defmodule Boxic.DMN.XMLWriterSchemaTest do
  use ExUnit.Case, async: true

  @model_namespace "https://www.omg.org/spec/DMN/20230324/MODEL/"

  @tag :schema
  test "generated decision-table XML validates against the packaged DMN 1.5 schema" do
    unless System.find_executable("xmllint") do
      flunk("xmllint is required for the focused schema compatibility test")
    end

    assert {:ok, model} =
             Boxic.DMN.load_xml("""
             <definitions xmlns="#{@model_namespace}" id="defs" name="Schema" namespace="urn:schema">
               <inputData id="age" name="Age">
                 <variable id="age_variable" name="Age" typeRef="number"/>
               </inputData>
               <decision id="decision" name="Decision">
                 <variable id="decision_variable" name="Decision" typeRef="string"/>
                 <informationRequirement><requiredInput href="#age"/></informationRequirement>
                 <decisionTable id="table">
                   <input id="input">
                     <inputExpression typeRef="number"><text>Age</text></inputExpression>
                   </input>
                   <output id="output" name="result" typeRef="string"/>
                   <rule id="rule">
                     <inputEntry><text>&gt;= 18</text></inputEntry>
                     <outputEntry><text>"adult"</text></outputEntry>
                   </rule>
                 </decisionTable>
               </decision>
             </definitions>
             """)

    assert {:ok, xml} = Boxic.DMN.encode_xml(model)

    assert_schema_valid(xml)
  end

  @tag :schema
  test "generated imports, BKMs, boxed contexts, and decision services validate against the schema" do
    assert {:ok, model} =
             Boxic.DMN.inspect_xml("""
             <definitions xmlns="#{@model_namespace}" id="defs" name="Boxed schema" namespace="urn:boxed">
               <import name="types" namespace="urn:types"
                 locationURI="types.dmn" importType="#{@model_namespace}"/>
               <businessKnowledgeModel id="identity" name="Identity">
                 <variable id="identity_variable" name="Identity"/>
                 <encapsulatedLogic>
                   <formalParameter id="value_parameter" name="value"/>
                   <literalExpression><text>value</text></literalExpression>
                 </encapsulatedLogic>
               </businessKnowledgeModel>
               <decision id="context" name="Context">
                 <context id="context_expression">
                   <contextEntry id="value">
                     <variable id="value_variable" name="value"/>
                     <literalExpression><text>1</text></literalExpression>
                   </contextEntry>
                   <contextEntry id="result">
                     <literalExpression><text>value</text></literalExpression>
                   </contextEntry>
                 </context>
               </decision>
               <decisionService id="service" name="Service">
                 <outputDecision href="#context"/>
               </decisionService>
             </definitions>
             """)

    assert {:ok, xml} = Boxic.DMN.encode_xml(model)
    assert_schema_valid(xml)
  end

  defp assert_schema_valid(xml) do
    path =
      Path.join(
        System.tmp_dir!(),
        "boxic-writer-schema-#{System.unique_integer([:positive])}.dmn"
      )

    on_exit(fn -> File.rm(path) end)
    File.write!(path, xml)

    schema = Path.expand("../priv/schema/dmn-1.5/DMN15.xsd", __DIR__)

    {output, status} =
      System.cmd("xmllint", ["--noout", "--schema", schema, path], stderr_to_stdout: true)

    assert status == 0, output
  end
end
