alias Boxic.DMN.Model

alias Boxic.DMN.Model.{
  Decision,
  DecisionRule,
  DecisionTable,
  Definitions,
  InputClause,
  OutputClause
}

build_model = fn rule_count ->
  rules =
    for index <- 1..rule_count do
      %DecisionRule{
        id: "rule_#{index}",
        input_entries: [Integer.to_string(index), "-"],
        output_entries: [Integer.to_string(index)]
      }
    end

  table = %DecisionTable{
    id: "benchmark_table",
    hit_policy: "UNIQUE",
    inputs: [
      %InputClause{id: "input_a", expression: "a", type_ref: "number"},
      %InputClause{id: "input_b", expression: "b", type_ref: "number"}
    ],
    outputs: [%OutputClause{id: "output", name: "result", type_ref: "number"}],
    rules: rules
  }

  %Model{
    definitions: %Definitions{
      id: "benchmark",
      name: "XML writer benchmark",
      namespace: "urn:boxic:benchmark"
    },
    source_profile: :dmn_1_4,
    serialization_fidelity: :complete,
    decisions: %{
      "decision" => %Decision{id: "decision", name: "Decision", expression: table}
    }
  }
end

IO.puts("rules,elapsed_ms,output_bytes,process_memory_bytes")

for rule_count <- [100, 1_000, 10_000] do
  model = build_model.(rule_count)

  {elapsed_us, {:ok, xml}} =
    :timer.tc(fn -> Boxic.DMN.encode_xml(model, format: :compact) end)

  {:memory, memory} = Process.info(self(), :memory)

  IO.puts(
    Enum.join(
      [
        rule_count,
        Float.round(elapsed_us / 1_000, 3),
        byte_size(xml),
        memory
      ],
      ","
    )
  )
end
