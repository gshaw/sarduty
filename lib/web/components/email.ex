defmodule Web.Components.Email do
  @moduledoc """
  An email address to reach someone by: a mailto: link with a copy button after it. For
  an address shown as who did something, or inside a sentence, write it as text. See
  /styles/email.
  """
  use Phoenix.Component

  import Web.Components.CopyButton, only: [copy_button: 1]

  attr :id, :string, required: true, doc: "the copy button's id"
  attr :email, :string, default: nil
  attr :missing, :string, default: nil, doc: "shown, as a hint, when there's no email"

  def email(assigns) do
    ~H"""
    <span :if={present?(@email)} class="break-all"><.copy_button
      id={@id}
      text={@email}
      href={"mailto:#{@email}"}
      value={@email}
      label="Copy email"
    /></span>
    <span :if={!present?(@email) and @missing} class="hint">{@missing}</span>
    """
  end

  defp present?(email), do: is_binary(email) and String.trim(email) != ""
end
