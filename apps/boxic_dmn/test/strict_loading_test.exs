defmodule Boxic.DMN.StrictLoadingTest do
  use ExUnit.Case, async: false

  @model_namespace "https://www.omg.org/spec/DMN/20230324/MODEL/"

  test "strictly loads a schema-valid native DMN 1.5 model" do
    assert {:ok, model} = Boxic.DMN.load_xml(valid_xml())
    assert model.source_profile == :dmn_1_5
    assert :ok = Boxic.DMN.validate_xml_schema(valid_xml())
  end

  test "reports normative schema violations as structured diagnostics" do
    invalid =
      String.replace(
        valid_xml(),
        ~s[ namespace="urn:strict"],
        ""
      )

    assert {:error, [diagnostic]} = Boxic.DMN.load_xml(invalid)
    assert diagnostic.code == :xml_schema_invalid
    assert diagnostic.category == :xml_schema
  end

  test "older profiles require explicit inspection and are not executable loads" do
    legacy =
      String.replace(
        valid_xml(),
        @model_namespace,
        "https://www.omg.org/spec/DMN/20211108/MODEL/"
      )

    assert {:ok, inspected} = Boxic.DMN.inspect_xml(legacy)
    assert inspected.source_profile == :dmn_1_4

    assert {:error, [diagnostic]} = Boxic.DMN.load_xml(legacy)
    assert diagnostic.code == :dmn_version_mismatch
    assert diagnostic.category == :executable_profile
  end

  test "expression language inherits from definitions and unsupported overrides are rejected" do
    inherited =
      String.replace(
        valid_xml(),
        "<definitions ",
        "<definitions expressionLanguage=\"https://www.omg.org/spec/DMN/20230324/FEEL/\" "
      )

    assert {:ok, model} = Boxic.DMN.load_xml(inherited)
    assert model.decisions["decision"].expression.expression_language == nil

    unsupported =
      String.replace(
        valid_xml(),
        "<literalExpression>",
        "<literalExpression expressionLanguage=\"urn:example:javascript\">"
      )

    assert {:error, diagnostics} = Boxic.DMN.load_xml(unsupported)
    assert Enum.any?(diagnostics, &(&1.code == :unsupported_expression_language))
  end

  test "rejects DTD and entity declarations before XML parsing" do
    xml = """
    <!DOCTYPE definitions [
      <!ENTITY secret SYSTEM "file:///etc/passwd">
    ]>
    #{valid_xml()}
    """

    assert {:error, [diagnostic]} = Boxic.DMN.inspect_xml(xml)
    assert diagnostic.code == :doctype_forbidden
  end

  test "inspection enforces a bounded XML nesting depth" do
    nested = String.duplicate("<extensionElements>", 257)
    closing = String.duplicate("</extensionElements>", 257)

    xml =
      """
      <definitions xmlns="#{@model_namespace}" id="defs" name="Deep" namespace="urn:deep">
      #{nested}#{closing}
      </definitions>
      """

    assert {:error, [diagnostic]} = Boxic.DMN.inspect_xml(xml)
    assert diagnostic.code == :xml_depth_limit_exceeded
  end

  test "inspection rejects unbounded XML names without growing the atom table" do
    assert {:error, [_diagnostic]} =
             Boxic.DMN.inspect_xml("""
             <definitions xmlns="#{@model_namespace}" id="warm" name="Warm" namespace="urn:warm">
               <boxicWarmUnknown/>
             </definitions>
             """)

    atom_count = :erlang.system_info(:atom_count)
    unknown = "boxicUnknown#{System.unique_integer([:positive])}"

    assert {:error, [diagnostic]} =
             Boxic.DMN.inspect_xml("""
             <definitions xmlns="#{@model_namespace}" id="probe" name="Probe" namespace="urn:probe">
               <#{unknown}/>
             </definitions>
             """)

    assert diagnostic.code == :unsupported_xml_name
    assert :erlang.system_info(:atom_count) == atom_count
  end

  test "capability validation distinguishes evaluation from serialization" do
    assert {:ok, model} = Boxic.DMN.load_xml(valid_xml())
    assert :ok = Boxic.DMN.validate(model, for: :evaluation)
    assert :ok = Boxic.DMN.validate(model, for: :serialization)

    inspected =
      %{model | source_profile: :dmn_1_4, serialization_fidelity: {:lossy, [:documentation]}}

    assert {:error, evaluation_diagnostics} =
             Boxic.DMN.validate(inspected, for: :evaluation)

    assert Enum.any?(evaluation_diagnostics, &(&1.code == :dmn_version_mismatch))

    assert {:error, serialization_diagnostics} =
             Boxic.DMN.validate(inspected, for: :serialization)

    assert Enum.any?(serialization_diagnostics, &(&1.category == :serialization))
  end

  test "XML loading resolves imports only from an explicit source" do
    fixture_dir = Path.join(__DIR__, "fixtures/imports")
    main = File.read!(Path.join(fixture_dir, "main.dmn"))
    library = File.read!(Path.join(fixture_dir, "library.dmn"))

    assert {:error, [diagnostic]} = Boxic.DMN.load_xml(main)
    assert diagnostic.code == :missing_import

    assert {:ok, model} =
             Boxic.DMN.load_xml(main,
               imports: %{"urn:boxic:test:library" => library}
             )

    assert Map.has_key?(model.bkms, "urn:boxic:test:library#greet")
  end

  defp valid_xml do
    """
    <definitions xmlns="#{@model_namespace}"
      id="defs" name="Strict" namespace="urn:strict">
      <decision id="decision" name="Decision">
        <literalExpression><text>1</text></literalExpression>
      </decision>
    </definitions>
    """
  end
end
