defmodule Boxic.ArchitectureTest do
  use ExUnit.Case, async: true

  test "umbrella applications preserve the FEEL to DMN to TCK dependency direction" do
    feel_dependencies = Application.spec(:boxic_feel, :applications)
    dmn_dependencies = Application.spec(:boxic_dmn, :applications)
    tck_dependencies = Application.spec(:boxic_dmn_tck, :applications)

    refute :boxic_dmn in feel_dependencies
    refute :boxic_dmn_tck in feel_dependencies
    assert :boxic_feel in dmn_dependencies
    refute :boxic_dmn_tck in dmn_dependencies
    assert :boxic_dmn in tck_dependencies
  end
end
