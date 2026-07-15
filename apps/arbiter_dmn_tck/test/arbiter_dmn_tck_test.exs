defmodule Arbiter.DMN.TCKTest do
  use ExUnit.Case

  alias Arbiter.DMN.TCK
  alias Arbiter.DMN.TCK.Loader
  alias Arbiter.DMN.TCK.Runner

  test "loads vendored fixture cases across groups" do
    cases = Loader.load_all()

    assert length(cases) >= 6
    assert Enum.any?(cases, &(&1.group == "0001-literal"))
    assert Enum.any?(cases, &(&1.group == "0002-feel-core"))
  end

  test "core profile regression baseline passes" do
    result = TCK.run(label: "core")

    assert result.summary.total >= 6
    assert result.summary.failed == 0
    assert result.summary.error == 0
    assert result.summary.passed == result.summary.total
  end

  test "single known case passes through runner" do
    case_entry =
      Loader.load_all()
      |> Enum.find(&(&1.group == "0001-literal" and &1.id == "001"))

    assert case_entry

    result = Runner.execute(case_entry)
    assert result.status == :passed
    assert result.actual == "hello from arbiter"
  end
end
