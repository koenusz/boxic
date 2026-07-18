defmodule Boxic.InspectHexPackage do
  @moduledoc false

  @outer_files ~w(VERSION CHECKSUM metadata.config contents.tar.gz)
  @required_files ~w(mix.exs README.md LICENSE CHANGELOG.md)
  @forbidden_prefixes ~w(test/ compatibility/ artifacts/ scripts/ tck/)

  def run([app, archive]) when app in ~w(boxic_feel boxic_dmn) do
    archive = Path.expand(archive)
    {:ok, outer} = :erl_tar.extract(String.to_charlist(archive), [:memory])
    outer_names = Enum.map(outer, fn {name, _contents} -> to_string(name) end)
    assert_equal!("outer archive files", Enum.sort(outer_names), Enum.sort(@outer_files))

    metadata = outer |> fetch!("metadata.config") |> consult_metadata!()
    assert_equal!("package name", metadata["name"], app)
    assert_equal!("package version", metadata["version"], "0.1.0")
    assert_equal!("package licenses", metadata["licenses"], ["Apache-2.0"])

    files =
      outer
      |> fetch!("contents.tar.gz")
      |> then(&:erl_tar.extract({:binary, &1}, [:memory, :compressed]))
      |> case do
        {:ok, entries} -> Enum.map(entries, fn {name, _contents} -> to_string(name) end)
        {:error, reason} -> Mix.raise("cannot inspect package contents: #{inspect(reason)}")
      end

    Enum.each(@required_files, fn required ->
      unless required in files, do: Mix.raise("#{app} package is missing #{required}")
    end)

    unless Enum.any?(files, &String.starts_with?(&1, "lib/")) do
      Mix.raise("#{app} package contains no library source")
    end

    case Enum.find(files, fn file ->
           Enum.any?(@forbidden_prefixes, &String.starts_with?(file, &1))
         end) do
      nil -> :ok
      forbidden -> Mix.raise("#{app} package contains forbidden file #{forbidden}")
    end

    verify_requirements!(app, metadata["requirements"])

    IO.puts(
      "Hex package inspection passed: #{app} #{metadata["version"]}, #{length(files)} files"
    )
  end

  def run(_args),
    do: Mix.raise("usage: mix run scripts/inspect_hex_package.exs APP ARCHIVE.tar")

  defp consult_metadata!(contents) do
    path =
      Path.join(
        System.tmp_dir!(),
        "boxic-metadata-#{System.unique_integer([:positive, :monotonic])}.config"
      )

    try do
      File.write!(path, contents)
      {:ok, terms} = :file.consult(String.to_charlist(path))

      Map.new(terms, fn {key, value} ->
        {to_string(key), normalize(value)}
      end)
    after
      File.rm(path)
    end
  end

  defp verify_requirements!("boxic_feel", requirements) do
    names = Enum.map(requirements, &requirement_name/1)
    assert_equal!("boxic_feel dependencies", Enum.sort(names), ~w(decimal tzdata))
  end

  defp verify_requirements!("boxic_dmn", requirements) do
    case Enum.find(requirements, &(requirement_name(&1) == "boxic_feel")) do
      nil ->
        Mix.raise("boxic_dmn package does not depend on boxic_feel")

      requirement ->
        requirement = requirement |> normalize() |> Map.new()
        assert_equal!("boxic_feel requirement", requirement["requirement"], "~> 0.1.0")
    end
  end

  defp requirement_name(requirement) do
    requirement
    |> normalize()
    |> Map.new()
    |> Map.fetch!("name")
  end

  defp fetch!(entries, wanted) do
    case Enum.find(entries, fn {name, _contents} -> to_string(name) == wanted end) do
      {_name, contents} -> contents
      nil -> Mix.raise("archive is missing #{wanted}")
    end
  end

  defp assert_equal!(_label, value, value), do: :ok

  defp assert_equal!(label, actual, expected),
    do: Mix.raise("#{label}: expected #{inspect(expected)}, got #{inspect(actual)}")

  defp normalize(value) when is_binary(value), do: to_string(value)
  defp normalize(value) when is_list(value), do: Enum.map(value, &normalize/1)
  defp normalize({key, value}), do: {normalize(key), normalize(value)}
  defp normalize(value), do: value
end

Boxic.InspectHexPackage.run(System.argv())
