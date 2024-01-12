defmodule Service.Temp do
  alias Service.Random

  def path, do: path(extension: "")

  def path(extension: extension) do
    Path.join(System.tmp_dir!(), "#{Random.hex()}#{extension}")
  end
end
