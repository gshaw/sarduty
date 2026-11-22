defmodule Web.Components.ThemeSwitch do
  @moduledoc """
  System, Light, and Dark, in the account menu and the style guide. A device with no
  choice follows the system. theme.js saves a choice for this device and reloads the page,
  so Safari's toolbar follows; Web.Theme reads it back. See /styles/top-bar.
  """
  use Phoenix.Component

  attr :id, :string, required: true

  # LiveView renders it without knowing the theme, so theme.js marks the pressed button
  # and phx-update="ignore" stops a patch from clearing the mark.
  def theme_switch(assigns) do
    ~H"""
    <div class="theme-choice">
      <span id={"#{@id}-label"}>Theme</span>
      <div
        id={@id}
        class="theme-switch"
        role="group"
        aria-labelledby={"#{@id}-label"}
        phx-hook="ThemeSwitch"
        phx-update="ignore"
      >
        <button type="button" data-theme-choice="">System</button>
        <button type="button" data-theme-choice="light">Light</button>
        <button type="button" data-theme-choice="dark">Dark</button>
      </div>
    </div>
    """
  end
end
