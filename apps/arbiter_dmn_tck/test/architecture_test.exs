defmodule Arbiter.ArchitectureTest do
  use ExUnit.Case, async: true

  test "umbrella applications preserve the FEEL to DMN to TCK dependency direction" do
    feel_dependencies = Application.spec(:arbiter_feel, :applications)
    dmn_dependencies = Application.spec(:arbiter_dmn, :applications)
    tck_dependencies = Application.spec(:arbiter_dmn_tck, :applications)

    refute :arbiter_dmn in feel_dependencies
    refute :arbiter_dmn_tck in feel_dependencies
    assert :arbiter_feel in dmn_dependencies
    refute :arbiter_dmn_tck in dmn_dependencies
    assert :arbiter_dmn in tck_dependencies
  end
end
