#!/usr/bin/env bash
set -euo pipefail

root_license="LICENSE"
package_licenses=(
  "apps/boxic_feel/LICENSE"
  "apps/boxic_dmn/LICENSE"
)

if [[ ! -f "$root_license" ]]; then
  echo "Missing root license: $root_license" >&2
  exit 1
fi

for package_license in "${package_licenses[@]}"; do
  if [[ ! -f "$package_license" ]]; then
    echo "Missing package license: $package_license" >&2
    exit 1
  fi

  if ! cmp -s "$root_license" "$package_license"; then
    echo "Package license differs from $root_license: $package_license" >&2
    exit 1
  fi
done

echo "Boxic license files are present and identical."
