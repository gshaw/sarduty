defmodule Web.Components.ThemeSwitch do
  @moduledoc """
  System, Light, and Dark, as a choice switch, on Account settings and in the style guide:
  icons and names, icons alone for page content, or names alone where space is tight.
  A device with no choice follows the system. theme.js posts a choice once the knob has
  slid; Web.ThemeController saves it for this device and comes back to the page, so
  Safari's toolbar picks up the new theme too. A choice that looks the same on this device
  saves in the background instead, and a `phx-hook="ThemeSaved"` shows its toast. See /styles/switches.
  """
  use Phoenix.Component

  import Web.Components.ChoiceSwitch, only: [choice_switch: 1]

  @choices [{"system", "System"}, {"light", "Light"}, {"dark", "Dark"}]
  @icon %{"system" => "monitor", "light" => "sun", "dark" => "moon"}

  attr :id, :string, required: true
  attr :theme, :string, default: nil, doc: "from Web.Theme: light, dark, or nil for System"
  attr :return_to, :string, required: true, doc: "the page to come back to"
  attr :show, :atom, values: [:both, :icons, :labels], default: :both
  attr :rest, :global, doc: "such as a phx-hook for the toast when no reload happens"

  def theme_switch(assigns) do
    ~H"""
    <.form for={%{}} id={@id} action="/theme" method="put" data-theme-form {@rest}>
      <input type="hidden" name="return_to" value={@return_to} />
      <.choice_switch
        id={"#{@id}-choice"}
        name="theme"
        label="Theme"
        value={@theme || "system"}
        options={options(@show)}
        labels={@show != :icons}
      />
    </.form>
    """
  end

  defp options(:labels), do: @choices
  defp options(_show), do: for({value, label} <- @choices, do: {value, label, @icon[value]})
end
