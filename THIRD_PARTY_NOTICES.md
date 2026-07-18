# Third-party notices

Boxic includes third-party material for development and compatibility testing.
That material remains subject to its upstream terms and is not relicensed by
Boxic's Apache-2.0 license.

## DMN Technology Compatibility Kit

- Project: DMN Technology Compatibility Kit
- Upstream repository: <https://github.com/dmn-tck/tck>
- Pinned commit: `0dbcaf9b98bc3af4e36d44a7aed95e9e85703a13`
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
