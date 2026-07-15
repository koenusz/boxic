defmodule Arbiter.DMNTest do
  use ExUnit.Case

  test "loads DMN and evaluates literal expression" do
    xml = """
    <definitions id=\"defs\" name=\"demo\" namespace=\"urn:demo\">
      <decision id=\"d1\" name=\"Greeting\">
        <literalExpression>
          <text>\"hello from dmn\"</text>
        </literalExpression>
      </decision>
    </definitions>
    """

    assert {:ok, model} = Arbiter.DMN.load(xml)
    assert :ok = Arbiter.DMN.validate(model)
    assert {:ok, "hello from dmn"} = Arbiter.DMN.evaluate(model, "Greeting", %{})
  end
end
