defmodule Web.Settings.HoursTagsLive do
  use Web, :live_view_app_layout

  import Web.Components.TeamSettingsTabs

  alias App.Model.Activity
  alias App.Model.Tag
  alias App.Model.Team
  alias App.Operation.SaveTeamHoursTags
  alias App.Repo

  # The D4H tags that say which hours an activity counts for (#323),
  # /teams/:subdomain/settings/hours-tags. The team's organization names some or all of
  # them; the team picks the rest from its own D4H tags.
  def mount(_params, _session, socket) do
    team = Repo.preload(socket.assigns.current_team, :organization)

    socket =
      socket
      |> assign(page_title: "Team settings · Hours tags", team: team)
      |> assign(organization_tags: Activity.organization_hours_tags(team))
      |> assign(titles: team.id |> Tag.get_all() |> Enum.map(& &1.title) |> Enum.uniq())
      |> then(
        &assign_form(&1, Team.build_hours_tags_changeset(team, &1.assigns.organization_tags))
      )

    {:ok, socket}
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "team"))

  @doc "The kinds of hours tag: its field, label, the select's blank choice, and its hint."
  def kinds do
    [
      {:primary, :primary_hours_tag, "Primary hours tag", "Primary Hours (the default)",
       "Activities with this tag count as primary hours on tax credit letters."},
      {:secondary, :secondary_hours_tag, "Secondary hours tag", "Secondary Hours (the default)",
       "Activities with this tag count as secondary hours."},
      {:other, :other_hours_tag, "Other hours tag (optional)", "None",
       "The tag on activities that count for no hours, such as a social."}
    ]
  end

  @doc "The titles to offer: the team's D4H tags, and the saved one if D4H no longer has it."
  def options(titles, saved) do
    titles = titles ++ List.wrap(saved)
    titles |> Enum.uniq() |> Enum.sort()
  end

  def render(assigns) do
    ~H"""
    <.team_settings_tabs team={@current_team} current={:hours_tags} />
    <div class="measure">
      <p class="lead">
        The tags that say which hours an activity counts for on tax credit letters.
      </p>
      <p class="mb-6">
        Letters already made keep their hours when a tag changes.
      </p>
      <.form for={@form} id="hours-tags-form" phx-change="validate" phx-submit="save">
        <.error_summary form={@form} />
        <%= for {kind, field, label, prompt, hint} <- kinds() do %>
          <%= if org_tag = @organization_tags[kind] do %>
            <.input
              id={"hours-tag-#{kind}"}
              name={"locked_#{field}"}
              value={org_tag}
              label={label}
              disabled
            >
              Set by {@team.organization.short_name}. {hint}
            </.input>
          <% else %>
            <.input
              id={"hours-tag-#{kind}"}
              field={@form[field]}
              type="select"
              label={label}
              prompt={prompt}
              options={options(@titles, Map.get(@team, field))}
            >
              {hint}
            </.input>
          <% end %>
        <% end %>
        <.form_actions :if={Enum.any?(@organization_tags, fn {_kind, tag} -> is_nil(tag) end)}>
          <.button variant={:success}>Save settings</.button>
        </.form_actions>
      </.form>
    </div>
    """
  end

  def handle_event("validate", %{"team" => params}, socket) do
    changeset =
      Team.build_hours_tags_changeset(
        socket.assigns.team,
        socket.assigns.organization_tags,
        params
      )

    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", params, socket) do
    case SaveTeamHoursTags.call(socket.assigns.team, params["team"] || %{}) do
      {:ok, team} ->
        socket =
          socket
          |> assign(current_team: team, team: team)
          |> assign_form(Team.build_hours_tags_changeset(team, socket.assigns.organization_tags))
          |> put_flash(:info, "Hours tags saved.")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end
end
