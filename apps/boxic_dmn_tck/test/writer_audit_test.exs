defmodule Boxic.DMN.TCK.WriterAuditTest do
  use ExUnit.Case, async: true

  alias Boxic.DMN.TCK.WriterAudit

  test "separates supported, rejected, and failed models" do
    root =
      Path.join(
        System.tmp_dir!(),
        "boxic-writer-audit-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    supported = Path.join(root, "supported.dmn")
    rejected = Path.join(root, "rejected.dmn")
    failed = Path.join(root, "failed.dmn")

    File.write!(
      supported,
      """
      <definitions xmlns="https://www.omg.org/spec/DMN/20211108/MODEL/"
        id="defs" name="Supported" namespace="urn:supported">
        <decision id="decision" name="Decision">
          <literalExpression><text>1</text></literalExpression>
        </decision>
      </definitions>
      """
    )

    File.write!(
      rejected,
      """
      <definitions xmlns="https://www.omg.org/spec/DMN/20230324/MODEL/"
        id="defs" name="Rejected" namespace="urn:rejected">
        <decision id="decision" name="Decision">
          <literalExpression><text>1</text></literalExpression>
        </decision>
      </definitions>
      """
    )

    File.write!(failed, "<definitions>")

    result = WriterAudit.audit_paths([supported, rejected, failed])
    assert result.summary == %{total: 3, supported: 1, rejected: 1, failed: 1}

    assert Enum.find(result.results, &(&1.path == supported)).status == :supported
    assert Enum.find(result.results, &(&1.path == rejected)).status == :rejected
    assert Enum.find(result.results, &(&1.path == failed)).status == :failed
  end
end
