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

      {:passed_error, reason} ->
        %{case: test_case, status: :passed, actual: nil, error: reason}

      {:missing, reason} ->
        %{case: test_case, status: :missing, actual: nil, error: reason}

      {:unsupported, reason} ->
        %{case: test_case, status: :unsupported, actual: nil, error: reason}

      {:error, reason} ->
        %{case: test_case, status: :error, actual: nil, error: reason}
    end
  end

  defp run_case(%Case{load_error: {:missing, reason}}), do: {:missing, reason}
  defp run_case(%Case{load_error: reason}) when not is_nil(reason), do: {:error, reason}

  defp run_case(%Case{model_path: model_path} = test_case) do
    if not File.exists?(model_path) do
      {:missing, {:model_not_found, model_path}}
    else
      case evaluate(test_case) do
        {:ok, actual} when test_case.expect_error ->
          if Comparator.semantic_equal?(actual, test_case.expected) do
            {:passed, actual}
          else
            {:failed, actual}
          end

        {:ok, actual} ->
          if Comparator.semantic_equal?(actual, test_case.expected) do
            {:passed, actual}
          else
            {:failed, actual}
          end

        {:error, %Arbiter.FEEL.Error{code: :unsupported_expression} = error} ->
          {:unsupported, error}

        {:error, reason} when test_case.expect_error ->
          {:passed_error, reason}

        {:error, reason} ->
          {:error, reason}
      end
    end
  rescue
    exception -> {:error, exception}
  end

  defp evaluate(test_case) do
    with {:ok, model} <- Arbiter.DMN.load(test_case.model_path) do
      if test_case.metadata[:case_type] == "decisionService" do
        case Arbiter.DMN.evaluate_service(
               model,
               test_case.metadata[:invocable_name],
               test_case.inputs
             ) do
          {:ok, value} when is_map(value) ->
            {:ok, Map.get(value, test_case.decision_name, value)}

          result ->
            result
        end
      else
        Arbiter.DMN.evaluate(model, test_case.decision_name, test_case.inputs)
      end
    end
  end
end
