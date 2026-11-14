defmodule Web.Components.OrgLogo do
  @moduledoc """
  A team's or organization's logo at 32px, or its initials when it has none: beside its
  name or a heading, such as each section on Admins and the organization on General
  (#1076). See /styles/org-logo.
  """
  use Phoenix.Component

  attr :id, :string, required: true
  attr :src, :string, default: nil, doc: "the logo's URL, or nil for the initials"
  attr :name, :string, required: true, doc: "whose logo, for the initials"

  def org_logo(assigns) do
    ~H"""
    <img :if={@src} id={@id} src={@src} width="32" height="32" class="size-8 rounded" alt="" />
    <span :if={!@src} id={@id} class="logo-initials size-8">
      {Web.Navigation.team_initials(@name)}
    </span>
    """
  end
end
