defmodule App.Report.Error do
  @moduledoc """
  A mistake in a report query: the line it is on, or nil for the whole query, and a
  message that says how to fix it (docs/writing.md).
  """

  defstruct [:line, :message]

  def new(line, message), do: %__MODULE__{line: line, message: message}

  @doc "The message with its line, as the editor and the error summary show it."
  def text(%__MODULE__{line: nil, message: message}), do: message
  def text(%__MODULE__{line: line, message: message}), do: "Line #{line}: #{message}"
end
