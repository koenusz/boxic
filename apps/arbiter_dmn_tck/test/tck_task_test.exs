defmodule Mix.Tasks.TckTest do
  use ExUnit.Case

  test "rejects unsafe or unsupported option combinations before execution" do
    assert_task_error([], "select --all")
    assert_task_error(["--all", "--group", "0100-feel-constants"], "--all cannot")
    assert_task_error(["--format", "json", "--group", "0100-feel-constants"], "requires --report")

    assert_task_error(
      ["--format", "xml", "--report", "result.xml", "--group", "x"],
      "unknown report format"
    )

    assert_task_error(["--profile", "implemented"], "--profile requires --suite")
  end

  test "writes only the requested report format" do
    root = Path.join(System.tmp_dir!(), "arbiter-task-#{System.unique_integer([:positive])}")
    path = Path.join(root, "group.json")
    on_exit(fn -> File.rm_rf!(root) end)

    Mix.Task.reenable("tck")

    assert :ok =
             Mix.Tasks.Tck.run([
               "--group",
               "0100-feel-constants",
               "--report",
               path,
               "--format",
               "json"
             ])

    assert File.exists?(path)
    refute File.exists?(Path.rootname(path) <> ".csv")
    assert path |> File.read!() |> Jason.decode!() |> get_in(["summary", "passed"]) == 2
  end

  defp assert_task_error(args, message) do
    Mix.Task.reenable("tck")
    assert_raise Mix.Error, ~r/#{Regex.escape(message)}/, fn -> Mix.Tasks.Tck.run(args) end
  end
end
