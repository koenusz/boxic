# DMN 1.5 construct capability ledger

This ledger describes Boxic's public normalized-model surface. “Schema” means
the construct is accepted when used according to the packaged DMN 1.5 schema;
it does not mean every legal combination is modeled.

| Construct | Schema | Representation | Evaluation | Serialization | Authoring | Evidence / blocked diagnostic |
| --- | --- | --- | --- | --- | --- | --- |
| definitions metadata | valid | modeled | semantically inert | modeled | safe | `strict_loading_test.exs`, writer corpus |
| imports | valid | modeled | supported | modeled | restricted | explicit/file import tests; `:missing_import`, `:import_*` |
| item definitions/components | valid | modeled | supported | modeled | restricted | type and writer tests |
| input data/variables | valid | modeled | supported | modeled | restricted | evaluator and writer tests |
| decisions/requirements | valid | modeled | supported | modeled | restricted | evaluator, import, and writer tests |
| literal FEEL expressions | valid | modeled | supported | modeled | safe | strict language tests and FEEL corpus |
| decision tables | valid | modeled | supported | modeled | safe | hit-policy, authoring, writer tests |
| contexts | valid | modeled | supported | modeled | restricted | boxed-expression and writer tests |
| invocations | valid | modeled | supported | modeled | restricted | BKM and writer tests |
| function definitions/BKMs | valid | modeled | supported | modeled | restricted | recursive BKM and writer tests |
| relations/lists | valid | modeled | supported | modeled | restricted | boxed-expression and writer tests |
| conditional/filter/iterator expressions | valid | modeled | supported | modeled | restricted | boxed-expression and writer tests |
| decision services | valid | modeled | supported | modeled | restricted | service/environment and writer tests |
| descriptions/documentation | valid | not retained | semantically inert | blocked | blocked | `:serialization_fidelity_loss` |
| decision-table annotations | valid | not retained | semantically inert | blocked | blocked | `:serialization_fidelity_loss` |
| DMNDI diagrams | valid | not retained | semantically inert | blocked | blocked | `:serialization_fidelity_loss` |
| recognized pinned-TCK extensions | valid where schema permits | detected as fidelity loss | semantically inert | blocked | blocked | TCK evaluator profile plus `:serialization_fidelity_loss` |
| other extension elements/vendor names | valid where schema permits | not admitted to bounded inspection | unsupported | blocked | blocked | `:unsupported_xml_name` |
| unknown standard elements/attributes | potentially valid | not retained | unsupported | blocked | blocked | `:unsupported_xml_element` / fidelity loss |
| non-FEEL expression languages | valid declaration | modeled declaration | unsupported | restricted | blocked | `:unsupported_expression_language` |
| Java external functions | TCK extension | not modeled | unsupported | not applicable | blocked | selected `0076-feel-external-java` disposition |

Writable rows are exercised by a native DMN 1.5 corpus that checks schema
validity, deterministic second writes, normalized-model equivalence, and
evaluation equivalence. Content marked blocked is detected during inspection;
`encode_xml/2` refuses the model rather than silently dropping it. Boxic does
not currently claim opaque XML round-trip support.
