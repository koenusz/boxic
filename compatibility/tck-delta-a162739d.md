# TCK compatibility delta

- Previous pin: `0dbcaf9b98bc3af4e36d44a7aed95e9e85703a13`
- Current pin: `a162739daee85fb28e9d3bec2f306505992dae0f`
- Upstream `TestCases` tree: unchanged
- Review disposition: metadata-only pin refresh; no test case was added,
  removed, selected, skipped, or reclassified

| Suite | Metric | Before | After | Delta |
| --- | --- | ---: | ---: | ---: |
| FEEL | passed | 2,042 | 2,042 | 0 |
| FEEL | explicitly unsupported Java cases | 18 | 18 | 0 |
| FEEL | failed / missing / error | 0 | 0 | 0 |
| DMN 1.5 | passed | 1,485 | 1,485 | 0 |
| DMN 1.5 | failed / unsupported / missing / error | 0 | 0 | 0 |

The refreshed reports also correct the report schema and runtime metadata:
actual package versions are emitted, the executable specification is DMN 1.5,
and the MODEL/FEEL namespaces are recorded explicitly.
