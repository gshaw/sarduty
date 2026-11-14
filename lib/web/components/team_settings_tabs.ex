defmodule Web.Components.TeamSettingsTabs do
  use Web, :function_component

  alias App.Model.Team

  # Team settings is one link in the side navigation (#406); its pages are tabs under one
  # title, a topic each: the team and what it has turned on, then its members, who signs
  # its letters and forms, and its activities. Fields, after Members, is what each custom
  # field on its records means (#872). Chore categories shows with chores on, and Agents
  # with Agents on. The key, rarely needed, is Change access key from General (#727).

  attr :team, :map, required: true

  attr :current, :atom,
    required: true,
    values: [
      :general,
      :admins,
      :members,
      :fields,
      :features,
      :signer,
      :hours_tags,
      :places,
      :chore_categories,
      :mcp
    ]

  def team_settings_tabs(assigns) do
    assigns = assign(assigns, tabs: list(assigns.team))

    ~H"""
    <h1 class="title">Team settings</h1>
    <.tabs label="Team settings">
      <:tab :for={tab <- @tabs} navigate={tab.path} current={@current == tab.key}>
        {tab.label}
      </:tab>
    </.tabs>
    """
  end

  @doc """
  The tabs `team` shows, in order: `%{key:, label:, path:, words:}`. Top bar search finds
  each one by its label or its `words`, the ones people search for it by
  (docs/search.md). General's words are also its Change pages', which search leaves out:
  "logo" finds General, where Change logo is.
  """
  def list(team) do
    [
      tab(:general, "General", ~p"/teams/#{team}/settings",
        words: ~w(legal abbreviated address mailing city postal place time zone timezone logo
             contacts access key token api records organization names)
      ),
      tab(:admins, "Admins", ~p"/teams/#{team}/settings/admins", words: ~w(owner editor)),
      tab(:features, "Features", ~p"/teams/#{team}/settings/features",
        words: ~w(logins id cards certificates chores travel whiteboard)
      ),
      tab(:members, "Members", ~p"/teams/#{team}/settings/members",
        words: ~w(retiring attendance check)
      ),
      tab(:fields, "Fields", ~p"/teams/#{team}/settings/fields", words: ~w(custom)),
      tab(:signer, "Signer", ~p"/teams/#{team}/settings/signer", words: ~w(signature)),
      tab(:hours_tags, "Hours tags", ~p"/teams/#{team}/settings/hours-tags"),
      tab(:places, "Places", ~p"/teams/#{team}/settings/places")
    ] ++ optional(team)
  end

  # The tabs a feature turns on.
  defp optional(team) do
    chores =
      if Team.chores?(team),
        do: [
          tab(:chore_categories, "Chore categories", ~p"/teams/#{team}/settings/chore-categories")
        ],
        else: []

    agents =
      if team.mcp_enabled,
        do: [tab(:mcp, "Agents", ~p"/teams/#{team}/settings/mcp", words: ~w(mcp ai))],
        else: []

    chores ++ agents
  end

  defp tab(key, label, path, opts \\ []),
    do: %{key: key, label: label, path: path, words: Keyword.get(opts, :words, [])}

  @general ~w(team.name team.legal_name team.abbreviated_name team.mailing_address team.city
              team.postal_code)

  @doc """
  The tab that fills one of the team's values a letter or form reads, by its name, such
  as `team.signer`: General for its names and address, Signer for who signs (#995), or
  nil for one no tab fills.
  """
  def tab_for(name) when name in @general, do: :general
  def tab_for("team.signer" <> _rest), do: :signer
  def tab_for(_name), do: nil

  @doc """
  Where to fill team settings' `tab`, as `tab_for/1` names it: Change team for General's
  names and address (#1076), which General only shows, and the Signer tab.
  """
  def tab_path(team, :general), do: ~p"/teams/#{team}/settings/edit"
  def tab_path(team, :signer), do: ~p"/teams/#{team}/settings/signer"
end
