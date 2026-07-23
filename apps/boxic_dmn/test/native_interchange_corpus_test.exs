defmodule Boxic.DMN.NativeInterchangeCorpusTest do
  use ExUnit.Case, async: true

  @fixture_dir Path.join(__DIR__, "fixtures/interchange")

  @writable [
    {"literal.dmn", {:decision, "Literal Decision", %{}, Decimal.new(1)}},
    {"decision_table.dmn", {:decision, "Classification", %{"Age" => Decimal.new(21)}, "adult"}},
    {"boxed_service.dmn", {:service, "Boxed Service", [], Decimal.new(2)}}
  ]

  test "native DMN 1.5 corpus is deterministic, schema-valid, and semantically stable" do
    for {filename, evaluation} <- @writable do
      source = File.read!(Path.join(@fixture_dir, filename))
      assert {:ok, model} = Boxic.DMN.load_xml(source)
      assert :ok = Boxic.DMN.validate(model, for: :serialization)
      assert {:ok, expected} = evaluate(model, evaluation)

      assert {:ok, first_xml} = Boxic.DMN.encode_xml(model)
      assert :ok = Boxic.DMN.validate_xml_schema(first_xml)
      assert {:ok, reloaded} = Boxic.DMN.load_xml(first_xml)
      assert {:ok, second_xml} = Boxic.DMN.encode_xml(reloaded)

      assert first_xml == second_xml
      assert model.decisions == reloaded.decisions
      assert model.bkms == reloaded.bkms
      assert model.decision_services == reloaded.decision_services
      assert {:ok, ^expected} = evaluate(reloaded, evaluation)
    end
  end

  test "inspect-only corpus is rejected precisely instead of being silently written" do
    source = File.read!(Path.join(@fixture_dir, "inspect_only_documentation.dmn"))
    assert {:ok, model} = Boxic.DMN.load_xml(source)

    assert {:error, diagnostics} = Boxic.DMN.validate(model, for: :serialization)
    assert Enum.any?(diagnostics, &(&1.code == :lossy_serialization))
  end

  defp evaluate(model, {:decision, name, inputs, expected}) do
    with {:ok, ^expected} = result <- Boxic.DMN.evaluate(model, name, inputs), do: result
  end

  defp evaluate(model, {:service, name, arguments, expected}) do
    with {:ok, ^expected} = result <- Boxic.DMN.evaluate_service(model, name, arguments),
         do: result
  end
end
