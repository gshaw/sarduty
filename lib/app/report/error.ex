defmodule App.Report.Error do
  @moduledoc """
  A mistake in a report query: the line it is on, or nil for the whole query, the part of
  the page it's in, such as `"option draft"` (#784), and a message that says how to fix
  it (docs/writing.md).
  """

  defstruct [:line, :message, :part]

  def new(line, message), do: %__MODULE__{line: line, message: message}

  @doc "The error, said of a part of the page: `in_part(error, \"option draft\")`."
  def in_part(%__MODULE__{part: nil} = error, part), do: %{error | part: part}
  def in_part(%__MODULE__{} = error, _part), do: error

  @doc "The message with its line and part, as the editor and the error summary show it."
  def text(%__MODULE__{line: nil, part: nil, message: message}), do: message

  def text(%__MODULE__{line: nil, part: part, message: message}),
    do: "#{String.upcase(String.first(part))}#{String.slice(part, 1..-1//1)}: #{message}"

  def text(%__MODULE__{line: line, part: nil, message: message}), do: "Line #{line}: #{message}"

  def text(%__MODULE__{line: line, part: part, message: message}),
    do: "Line #{line}, #{part}: #{message}"
end
