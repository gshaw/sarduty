defmodule Web.Org.HoursTagsLive do
  use Web, :live_view_app_layout

  import Ecto.Query
  import Web.Components.OrgSettingsTabs

  alias App.Model.Organization
  alias App.Model.Tag
  alias App.Model.Team
  alias App.Operation.SaveOrganizationHoursTags
  alias App.Repo

  # Organization settings › Hours tags (#289, #512): the tags its teams count as primary,
  # secondary, and no hours. Each offers the tags its teams have, so a typo can't creep
  # in; the saved one stays an option even when no team has it.
  def mount(_params, _session, socket) do
    organization = socket.assigns.current_organization
    teams = Team |> where([t], t.organization_id == ^organization.id) |> Repo.all()

    socket =
      socket
      |> assign(page_title: "Organization settings · Hours tags")
      |> assign(teams: teams, tag_counts: teams |> Enum.map(& &1.id) |> Tag.team_counts())
      |> assign_form(Organization.build_hours_tags_changeset(organization, teams))

    {:ok, socket}
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))

  @doc "The kinds of hours tag: its field, label, and hint."
  def kinds do
    [
      {:primary, :primary_hours_tag, "Primary hours tag",
       "Activities with this tag count as primary hours on tax credit letters."},
      {:secondary, :secondary_hours_tag, "Secondary hours tag",
       "Activities with this tag count as secondary hours."},
      {:other, :other_hours_tag, "Other hours tag (optional)",
       "The tag on activities that count for no hours, such as a social."}
    ]
  end

  @doc "The titles to offer: the saved one if no team has it, then the teams' tags."
  def options(tag_counts, saved) do
    titles = Enum.map(tag_counts, & &1.title)
    if saved in [nil, ""] or saved in titles, do: titles, else: [saved | titles]
  end

  def render(assigns) do
    ~H"""
    <.org_settings_tabs organization={@current_organization} current={:hours_tags} />
    <div class="measure">
      <p class="lead">
        The tags that say which hours an activity counts for on its teams' tax credit letters.
      </p>
      <p class="mb-6">
        Leave one blank to let each team pick its own. Letters already made keep their hours
        when a tag changes.
      </p>
      <.empty_state :if={@teams == []} id="no-teams" title="No teams yet">
        The tags come from its teams. A SAR Duty site admin adds them.
      </.empty_state>
      <.form
        :if={@teams != []}
        for={@form}
        id="hours-tags-form"
        phx-change="validate"
        phx-submit="save"
      >
        <.error_summary form={@form} />
        <.input
          :for={{kind, field, label, hint} <- kinds()}
          id={"hours-tag-#{kind}"}
          field={@form[field]}
          type="combobox"
          clearable
          label={label}
          prompt="Each team picks its own"
          options={options(@tag_counts, Map.get(@current_organization, field))}
        >
          {hint}
          <span id={"hours-tag-#{kind}-teams"}>{team_count(@tag_counts, @form[field].value, @teams)}</span>
        </.input>
        <.form_actions>
          <.button variant={:success}>Save hours tags</.button>
        </.form_actions>
      </.form>
    </div>
    """
  end

  # "7 of 7 teams have this tag.", which catches a team without it.
  defp team_count(_tag_counts, value, _teams) when value in [nil, ""], do: nil

  defp team_count(tag_counts, value, teams) do
    count = Enum.find_value(tag_counts, 0, &(&1.title == value && &1.teams))

    "#{count} of #{Service.Format.count(length(teams), one: "%d team", many: "%d teams")} #{if count == 1, do: "has", else: "have"} this tag."
  end

  def handle_event("validate", %{"organization" => params}, socket) do
    changeset =
      socket.assigns.current_organization
      |> Organization.build_hours_tags_changeset(socket.assigns.teams, blank_to_nil(params))
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"organization" => params}, socket) do
    %{current_organization: organization, current_user: user} = socket.assigns

    case SaveOrganizationHoursTags.call(organization, blank_to_nil(params), user) do
      {:ok, organization} ->
        socket =
          socket
          |> assign(current_organization: organization)
          |> assign_form(
            Organization.build_hours_tags_changeset(organization, socket.assigns.teams)
          )
          |> put_flash(:info, "Hours tags saved.")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  # The combobox sends "" for its prompt; blank means each team picks its own.
  defp blank_to_nil(params),
    do: Map.new(params, fn {k, v} -> {k, if(v == "", do: nil, else: v)} end)
end
