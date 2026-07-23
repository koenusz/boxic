# Third-party notices

Boxic includes third-party material for development and compatibility testing.
That material remains subject to its upstream terms and is not relicensed by
Boxic's Apache-2.0 license.

## DMN Technology Compatibility Kit

- Project: DMN Technology Compatibility Kit
- Upstream repository: <https://github.com/dmn-tck/tck>
- Pinned commit: `a162739daee85fb28e9d3bec2f306505992dae0f`
- Vendored location: `vendor/dmn-tck`

The vendored snapshot preserves the upstream licensing information available
with the selected corpus:

- [`vendor/dmn-tck/LICENSE-ASL-2.0.txt`](vendor/dmn-tck/LICENSE-ASL-2.0.txt)
  contains the Apache License, Version 2.0.
- [`vendor/dmn-tck/README.md`](vendor/dmn-tck/README.md) contains the upstream
  project's additional statements about the availability and attribution of
  its test cases.

The vendored corpus is used only by Boxic's internal TCK harness. It is not
included in the `boxic_feel` or `boxic_dmn` Hex packages.

## OMG DMN 1.5 schemas

`boxic_dmn` includes the normative `DMN15.xsd`, `DMNDI15.xsd`, `DI.xsd`, and
`DC.xsd` machine-readable files published with
<https://www.omg.org/spec/DMN/1.5>. Their checksums and source are recorded in
`apps/boxic_dmn/priv/schema/dmn-1.5/MANIFEST`. These files remain subject to
the OMG specification notices and terms and are not relicensed by Boxic's
Apache-2.0 license.
