defmodule Web.FormOwner do
  @moduledoc """
  Who a Forms page is for: an organization, under `/orgs/:slug/forms` (#950), or one
  team, a Team settings tab under `/teams/:subdomain/settings/forms` (#1083). The same pages serve both, so each asks
  this for its owner, its paths, and the words that differ. A team's pages are a 404
  until SAR Duty turns team forms on for it, except the Forms tab and an organization's
  form's page, which every team's admins see read-only.
  """

  use Phoenix.VerifiedRoutes,
    endpoint: Web.Endpoint,
    router: Web.Router,
    statics: Web.static_paths()

  alias App.Model.Form
  alias App.Model.Organization
  alias App.Model.Team

  @doc """
  The page's owner from its assigns: `current_organization` on an organization's page,
  else `current_team`. Raises a 404 for a team with team forms off.
  """
  def get(%{current_organization: %Organization{} = organization}), do: organization
  def get(%{current_team: %Team{forms_enabled: true} = team}), do: team
  def get(_assigns), do: raise(Web.Status.NotFound)

  @doc """
  The owner of the Forms tab and a form's page, which every team has: the organization,
  or the team, with team forms on or off.
  """
  def viewer(%{current_organization: %Organization{} = organization}), do: organization
  def viewer(%{current_team: %Team{} = team}), do: team

  @doc """
  `{form, own?}`: the owner's own form `id`, or on a team's page, its organization's
  form testing or on, read-only. A 404 for any other, and for the team's own while team
  forms are off.
  """
  def form!(%Organization{} = organization, id),
    do: {Form.get(organization, id) || raise(Web.Status.NotFound), true}

  def form!(%Team{} = team, id) do
    own = team.forms_enabled && Form.get(team, id)

    cond do
      own -> {own, true}
      form = Form.get_organization_form(team, id) -> {form, false}
      true -> raise Web.Status.NotFound
    end
  end

  @doc "The owner's name in a sentence: an organization's short name, or the team's name."
  def name(%Organization{short_name: name}), do: name
  def name(%Team{name: name}), do: name

  @doc "Team settings, where a team's Forms tab is, for a page's trail; nil for an organization."
  def settings_path(%Team{} = team), do: ~p"/teams/#{team}/settings"
  def settings_path(%Organization{}), do: nil

  def forms_path(%Organization{} = organization), do: ~p"/orgs/#{organization}/forms"
  def forms_path(%Team{} = team), do: ~p"/teams/#{team}/settings/forms"

  def new_path(%Organization{} = organization), do: ~p"/orgs/#{organization}/forms/new"
  def new_path(%Team{} = team), do: ~p"/teams/#{team}/settings/forms/new"

  def form_path(%Organization{} = organization, %Form{} = form),
    do: ~p"/orgs/#{organization}/forms/#{form}"

  def form_path(%Team{} = team, %Form{} = form), do: ~p"/teams/#{team}/settings/forms/#{form}"

  @doc "Change form, where its admins write the form with AI writing (#1089)."
  def change_path(%Organization{} = organization, %Form{} = form),
    do: ~p"/orgs/#{organization}/forms/#{form}/edit"

  def change_path(%Team{} = team, %Form{} = form),
    do: ~p"/teams/#{team}/settings/forms/#{form}/edit"

  def page_path(%Organization{} = organization, %Form{} = form),
    do: ~p"/orgs/#{organization}/forms/#{form}/page"

  def page_path(%Team{} = team, %Form{} = form),
    do: ~p"/teams/#{team}/settings/forms/#{form}/page"

  def try_path(%Organization{} = organization, %Form{} = form),
    do: ~p"/orgs/#{organization}/forms/#{form}/try"

  def try_path(%Team{} = team, %Form{} = form), do: ~p"/teams/#{team}/settings/forms/#{form}/try"
end
