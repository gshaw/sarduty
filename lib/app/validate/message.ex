defmodule App.Validate.Message do
  # A team admin's own words in an email about an activity (#609): plain text, short
  # enough to read on one phone screen with the email's buttons.
  alias Service.Format

  @max_length 300

  def max_length, do: @max_length

  @doc "Trimmed, with Windows line breaks made plain, or nil when it's empty."
  def normalize(nil), do: nil

  def normalize(text) do
    case text |> String.replace("\r\n", "\n") |> String.trim() do
      "" -> nil
      message -> message
    end
  end

  @doc "Whether a normalized message is short enough."
  def fits?(nil), do: true
  def fits?(message), do: String.length(message) <= @max_length

  @doc "The hint's limit and the error's: \"300 characters\"."
  def limit_text, do: Format.count(@max_length, one: "%d character", many: "%d characters")

  def error_text, do: "Message must be #{limit_text()} or fewer."
end
