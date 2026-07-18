defmodule Boxic.DMN.XML.Loader do
  @moduledoc false

  defdelegate load(path_or_xml), to: Boxic.DMN.Engine
  defdelegate load_file(path), to: Boxic.DMN.Engine
  defdelegate load_xml(xml), to: Boxic.DMN.Engine
end
