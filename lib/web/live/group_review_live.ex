defmodule Web.GroupReviewLive do
  use Web, :live_view_app_layout

  alias App.Model.Group
  alias App.Model.Team
  alias App.Operation.ApplyGroupRuleChanges
  alias App.Operation.BuildGroupRulePreview
  alias App.Worker.RefreshTeamDataWorker

  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(App.PubSub, "team_refresh")
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    group = Group.find!(socket.assigns.current_team, params["id"])

    socket =
      socket
      |> assign(:page_title, "Review changes")
      |> assign(:group, group)
      |> load_preview()

    {:noreply, socket}
  end

  def handle_info({:team_refreshed, %Team{} = team}, socket) do
    cond do
      team.id != socket.assigns.current_team.id ->
        {:noreply, socket}

      Team.refresh_state(team.d4h_refresh_result) == :ok ->
        {:noreply, socket |> assign(:current_team, team) |> load_preview()}

      true ->
        {:noreply, assign(socket, :current_team, team)}
    end
  end

  def handle_event("select", params, socket) do
    {:noreply, assign(socket, :selected, params |> selected_ids() |> MapSet.new())}
  end

  def handle_event("refresh", _params, socket) do
    team = socket.assigns.current_team

    %{team_id: team.id}
    |> RefreshTeamDataWorker.new()
    |> Oban.insert()

    {:noreply, assign(socket, :current_team, %{team | d4h_refresh_result: "Refreshing"})}
  end

  def handle_event("apply", params, socket) do
    %{current_team: team, current_user: user, group: group} = socket.assigns
    group_path = ~p"/#{team.subdomain}/groups/#{group.id}"

    case ApplyGroupRuleChanges.call(team, group, user, selected_ids(params)) do
      {:ok, %{applied: applied, failed: 0}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Made #{count_changes(applied)} in D4H.")
         |> push_navigate(to: group_path)}

      {:ok, %{applied: applied, failed: failed}} ->
        message =
          "Made #{count_changes(applied)} in D4H. #{count_changes(failed)} failed; " <>
            "see Recent changes."

        {:noreply, socket |> put_flash(:error, message) |> push_navigate(to: group_path)}

      {:error, :no_team_key} ->
        {:noreply, put_flash(socket, :error, "Save a team D4H key in Team Settings first.")}

      {:error, :rules_broken} ->
        {:noreply, put_flash(socket, :error, "Fix the group's rules first.")}
    end
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
      <:item label="Groups" path={~p"/#{@current_team.subdomain}/groups"} />
      <:item label={@group.title} path={~p"/#{@current_team.subdomain}/groups/#{@group.id}"} />
      <:item label="Review changes" />
    </.breadcrumbs>

    <h1 class="title">Review changes</h1>
    <p class="text-secondary-1 mb-p">
      Clear the box next to anyone you want to skip. Changes are made in D4H right away,
      using the team's D4H key.
    </p>

    <div id="data-age" class="flex items-center gap-p mb-p text-sm">
      <span :if={refreshing?(@current_team)}>
        <.spinner size="size-4">Refreshing from D4H…</.spinner>
      </span>
      <span :if={failed?(@current_team)} id="refresh-error" class="text-danger-1">
        {String.replace_prefix(@current_team.d4h_refresh_result, "Error: ", "Refresh failed: ")}
      </span>
      <span :if={!refreshing?(@current_team) && @current_team.d4h_refreshed_at}>
        Data as of {Service.Format.datetime_short(
          @current_team.d4h_refreshed_at,
          @current_team.timezone
        )}
      </span>
      <.button
        id="refresh"
        size={:sm}
        phx-click="refresh"
        disabled={refreshing?(@current_team)}
      >
        Refresh from D4H
      </.button>
    </div>

    <p
      :if={is_nil(@current_team.d4h_access_key)}
      id="no-team-key"
      class="rounded bg-warning-1 text-warning-content px-p py-p05 mb-p"
    >
      Applying changes needs a team D4H key.
      <.a navigate={~p"/settings/team"}>Save one in Team Settings.</.a>
    </p>

    <p
      :if={@preview.missing_qualification_ids != []}
      id="rule-broken"
      class="rounded bg-warning-1 text-warning-content px-p py-p05 mb-p"
    >
      The group's rules name a qualification that is no longer in D4H. Fix the rules first.
    </p>

    <.form for={%{}} id="review-form" phx-change="select" phx-submit="apply">
      <.review_list
        id="review-remove"
        title="Remove from group"
        title_class="text-danger-1"
        rows={@preview.to_remove}
        selected={@selected}
      />
      <.review_list
        id="review-add"
        title="Add to group"
        title_class="text-success-1"
        rows={@preview.to_add}
        selected={@selected}
      />

      <p
        :if={@preview.to_add == [] && @preview.to_remove == []}
        id="no-changes"
        class="text-secondary-1 mb-p"
      >
        No changes. The group matches its rules.
      </p>

      <div class="flex gap-2">
        <.button
          id="apply"
          variant={:primary}
          disabled={MapSet.size(@selected) == 0 || is_nil(@current_team.d4h_access_key)}
          phx-disable-with="Applying…"
        >
          Apply {count_changes(MapSet.size(@selected))} in D4H
        </.button>
        <.button navigate={~p"/#{@current_team.subdomain}/groups/#{@group.id}"}>Cancel</.button>
      </div>
    </.form>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :title_class, :string, required: true
  attr :rows, :list, required: true
  attr :selected, :any, required: true

  defp review_list(assigns) do
    ~H"""
    <div :if={@rows != []} class="mb-p">
      <h2 class={["font-semibold mb-p05", @title_class]}>{@title} ({length(@rows)})</h2>
      <.table id={@id} rows={@rows} row_id={&"#{@id}-#{&1.member.id}"} class="w-full table-striped">
        <:col :let={row} label="" class="w-px">
          <input
            type="checkbox"
            id={"select-#{row.member.id}"}
            name="member_ids[]"
            value={row.member.id}
            checked={MapSet.member?(@selected, row.member.id)}
          />
        </:col>
        <:col :let={row} label="Member" class="md:w-1/3">
          <label for={"select-#{row.member.id}"}>{row.member.name}</label>
        </:col>
        <:col :let={row} label="Why">{row.reason}</:col>
      </.table>
    </div>
    """
  end

  defp load_preview(socket) do
    preview = BuildGroupRulePreview.for_group(socket.assigns.current_team, socket.assigns.group)
    everyone = Enum.map(preview.to_remove ++ preview.to_add, & &1.member.id)

    socket
    |> assign(:preview, preview)
    |> assign(:selected, MapSet.new(everyone))
  end

  # Member ids from the form. ApplyGroupRuleChanges ignores any the plan doesn't list.
  defp selected_ids(params) do
    params
    |> Map.get("member_ids", [])
    |> List.wrap()
    |> Enum.flat_map(fn id ->
      case Integer.parse(id) do
        {id, ""} -> [id]
        _ -> []
      end
    end)
  end

  defp count_changes(n), do: Service.Format.count(n, one: "%d change", many: "%d changes")

  defp refreshing?(team), do: Team.refresh_state(team.d4h_refresh_result) == :refreshing
  defp failed?(team), do: Team.refresh_state(team.d4h_refresh_result) == :failed
end
