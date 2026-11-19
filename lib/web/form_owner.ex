defmodule Web.FormOwner do
  @moduledoc """
  Who a Forms page is for: an organization, under `/orgs/:slug/forms` (#950), or one
  team, under `/teams/:subdomain/forms` (#1083). The same pages serve both, so each asks
  this for its owner, its paths, and the words that differ. A team's pages are a 404
  until SAR Duty turns team forms on for it.
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

  @doc "The owner's name in a sentence: an organization's short name, or the team's name."
  def name(%Organization{short_name: name}), do: name
  def name(%Team{name: name}), do: name

  def forms_path(%Organization{} = organization), do: ~p"/orgs/#{organization}/forms"
  def forms_path(%Team{} = team), do: ~p"/teams/#{team}/forms"

  def new_path(%Organization{} = organization), do: ~p"/orgs/#{organization}/forms/new"
  def new_path(%Team{} = team), do: ~p"/teams/#{team}/forms/new"

  def form_path(%Organization{} = organization, %Form{} = form),
    do: ~p"/orgs/#{organization}/forms/#{form}"

  def form_path(%Team{} = team, %Form{} = form), do: ~p"/teams/#{team}/forms/#{form}"

  def edit_path(%Organization{} = organization, %Form{} = form),
    do: ~p"/orgs/#{organization}/forms/#{form}/edit"

  def edit_path(%Team{} = team, %Form{} = form), do: ~p"/teams/#{team}/forms/#{form}/edit"

  def page_path(%Organization{} = organization, %Form{} = form),
    do: ~p"/orgs/#{organization}/forms/#{form}/page"

  def page_path(%Team{} = team, %Form{} = form), do: ~p"/teams/#{team}/forms/#{form}/page"

  def try_path(%Organization{} = organization, %Form{} = form),
    do: ~p"/orgs/#{organization}/forms/#{form}/try"

  def try_path(%Team{} = team, %Form{} = form), do: ~p"/teams/#{team}/forms/#{form}/try"
end
