defmodule Boxic.DMN.Evaluator do
  @moduledoc false

  defdelegate evaluate(model, decision_name, context), to: Boxic.DMN.Engine
  defdelegate evaluate(model, decision_name, context, opts), to: Boxic.DMN.Engine
  defdelegate evaluate_service(model, service_name, arguments), to: Boxic.DMN.Engine
end
