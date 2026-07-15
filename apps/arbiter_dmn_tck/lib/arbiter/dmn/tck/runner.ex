defmodule Arbiter.DMN.TCK.Runner do
  @moduledoc """
  Executes one TCK case through Arbiter.DMN.
  """

  alias Arbiter.DMN.TCK.Case
  alias Arbiter.DMN.TCK.Comparator

  @type result :: %{case: Case.t(), status: atom(), actual: term(), error: term()}

  @spec execute(Case.t()) :: result()
  def execute(%Case{} = test_case) do
    case run_case(test_case) do
      {:passed, actual} ->
        %{case: test_case, status: :passed, actual: actual, error: nil}

      {:failed, actual} ->
        %{case: test_case, status: :failed, actual: actual, error: nil}

      {:missing, reason} ->
        %{case: test_case, status: :missing, actual: nil, error: reason}

      {:unsupported, reason} ->
        %{case: test_case, status: :unsupported, actual: nil, error: reason}

      {:error, reason} ->
        %{case: test_case, status: :error, actual: nil, error: reason}
    end
  end

  defp run_case(%Case{model_path: model_path} = test_case) do
    if not File.exists?(model_path) do
      {:missing, {:model_not_found, model_path}}
    else
      with {:ok, model} <- Arbiter.DMN.load(model_path),
           {:ok, actual} <- Arbiter.DMN.evaluate(model, test_case.decision_name, test_case.inputs) do
        if Comparator.semantic_equal?(actual, test_case.expected) do
          {:passed, actual}
        else
          {:failed, actual}
        end
      else
        {:error, %Arbiter.FEEL.Error{code: :unsupported_expression} = error} ->
          {:unsupported, error}

        {:error, reason} ->
          {:error, reason}
      end
    end
  rescue
    exception -> {:error, exception}
  end
end
