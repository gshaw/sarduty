defmodule Web.Settings.AccessKeyLive do
  use Web, :live_view_app_layout

  import Web.Components.CopyButton, only: [copy_button: 1]
  import Web.Components.TeamSettingsTabs

  alias App.Adapter.D4H
  alias App.Model.D4HAccess
  alias App.Model.Member
  alias App.Model.Team
  alias App.Operation.CheckTeamKey
  alias App.Operation.SaveTeamKey
  alias App.Repo

  # Team settings' Access key tab (#727), last because it's rarely needed: who the key
  # belongs to, what D4H refuses it, and how to replace it. A D4H key acts as the member
  # who made it, so an Editor's key can do less than an Owner's. A Records key can do
  # everything, so a Records team gets no check.
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(page_title: "Team settings · Access key")
      |> assign_team(socket.assigns.current_team)
      |> assign_form(Team.build_key_changeset(socket.assigns.current_team))

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.team_settings_tabs team={@current_team} current={:access_key} />
    <div class="measure">
      <p :if={!@records?} class="lead">
        SAR Duty uses this key for everything it reads from D4H and sends to it.
      </p>
      <p :if={@records?} class="lead">
        SAR Duty uses this key to read and change your team's records in SAR Duty Records.
      </p>

      <.banner :if={@refused != []} kind={:warning} title="D4H limits this key" id="key-refused">
        <p>
          {refused_text(@current_team, @level, @refused)} Ask a D4H Owner to make {@current_team.d4h_access_key_owner} an Owner, then select Check again.
        </p>
        <p class="mb-0">
          <.copy_button
            id="copy-key-ask"
            value={ask_message(@current_team, @refused)}
            label="Copy message"
            text="Copy a message for your D4H Owner"
          />
        </p>
      </.banner>

      <p :if={is_nil(@current_team.d4h_access_key)} id="team-key-missing" class="callout">
        SAR Duty cannot reach {D4H.service_name(@current_team)} for this team. Save a {D4H.key_name(
          @current_team
        )}.
      </p>

      <dl :if={@current_team.d4h_access_key} id="team-key-owner">
        <dt :if={!@records?}>Belongs to</dt>
        <dt :if={@records?}>Name in SAR Duty Records</dt>
        <dd>{owner_text(@current_team, @level)}</dd>
        <dt>Saved</dt>
        <dd id="team-key-saved">{saved_text(@current_team)}</dd>
      </dl>

      <p
        :if={!@records? and !Team.key_owner_is_sar_duty?(@current_team)}
        id="team-key-advice"
        class="callout"
      >
        Create the key from a D4H member named "SAR Duty" rather than a person. D4H history then
        shows SAR Duty for changes made here, and the key keeps working when people leave the
        team. In D4H, add a member named SAR Duty with Owner access.
      </p>

      <section :if={!@records? and @current_team.d4h_access_key} id="key-rights">
        <h2 class="heading mt-8">What the key can do</h2>
        <p :if={is_nil(@current_team.d4h_permissions_checked_at)} id="key-unchecked">
          SAR Duty has not checked this key yet.
        </p>
        <p :if={@current_team.d4h_permissions_checked_at && @refused == []} id="key-can-all">
          The key can do everything SAR Duty does.
        </p>
        <p :if={@refused != []} id="key-can-most">The key can do everything else SAR Duty does.</p>
        <.table
          :if={@refused != []}
          id="key-refused-rows"
          rows={@refused}
          row_id={&"key-refused-#{&1.id}"}
          class="table-striped"
        >
          <:col :let={feature} label="D4H refuses">
            <span class="block font-semibold">{feature.name}</span>
            <span class="hint block">{feature.what}</span>
          </:col>
        </.table>
        <p :if={@current_team.d4h_permissions_checked_at} id="key-checked" class="hint mt-4">
          Checked {Service.Format.datetime_medium(
            @current_team.d4h_permissions_checked_at,
            @current_team.timezone
          )}. SAR Duty checks every night and when you save a key.
        </p>
        <p class="mt-4">
          <.button type="button" id="check-key" phx-click="check" phx-disable-with="Checking…">
            Check again
          </.button>
        </p>
      </section>

      <h2 class="heading mt-8">
        {if @current_team.d4h_access_key, do: "Replace the key", else: "Save a key"}
      </h2>
      <.form for={@form} id="team_key_form" phx-submit="save">
        <.input
          field={@form[:new_d4h_access_key]}
          label={"New #{D4H.key_name(@current_team)}"}
          type="password"
          autocomplete="off"
        >
          <%= if @records? do %>
            Create it on API keys in SAR Duty Records, and paste it here.
            <span class="action block mt-1">
              <.a
                id="records-keys"
                external={true}
                href={"https://#{D4H.records_host()}/teams/#{@current_team.subdomain}/keys"}
              >Create a key in SAR Duty Records</.a>
            </span>
          <% else %>
            Create it in D4H while logged in as the member the key should belong to.
            <span class="action block mt-1">
              <.a
                external={true}
                href="https://help.d4h.com/article/377-obtaining-an-api-access-key"
              >Create a D4H access key</.a>
            </span>
          <% end %>
        </.input>
        <.form_actions>
          <.button variant={:success} phx-disable-with="Saving…">Save key</.button>
        </.form_actions>
      </.form>
    </div>
    """
  end

  defp assign_team(socket, %Team{} = team) do
    records? = D4H.records?(team)

    assign(socket,
      current_team: team,
      records?: records?,
      refused: D4HAccess.refused(team.d4h_permissions),
      level: if(!records?, do: key_level(team))
    )
  end

  defp assign_form(socket, %{} = source) do
    assign(socket, :form, to_form(source, as: "form"))
  end

  # The key member's D4H access level, Owner or Editor, from SAR Duty's copy of members.
  defp key_level(%Team{d4h_access_key_member_id: nil}), do: nil

  defp key_level(%Team{} = team) do
    case Repo.get_by(Member, team_id: team.id, d4h_member_id: team.d4h_access_key_member_id) do
      %Member{d4h_permission: permission} when permission in [0, 1] ->
        Member.permission_label(permission)

      _other ->
        nil
    end
  end

  defp owner_text(%Team{d4h_access_key_owner: nil}, _level), do: "Not known yet"
  defp owner_text(%Team{d4h_access_key_owner: owner}, nil), do: owner
  defp owner_text(%Team{d4h_access_key_owner: owner}, level), do: "#{owner}, an #{level} in D4H"

  defp saved_text(%Team{d4h_access_key_saved_at: nil}), do: "Before SAR Duty kept the date"

  defp saved_text(%Team{} = team),
    do: Service.Format.date_long(team.d4h_access_key_saved_at, team.timezone)

  # "Sam Rivers is an Editor in D4H, and D4H refuses an Editor's key to change groups."
  defp refused_text(team, level, refused) do
    what = refused |> Enum.map(&String.downcase(&1.name)) |> Service.Format.and_list()

    if level do
      "#{team.d4h_access_key_owner} is an #{level} in D4H, and D4H refuses an #{level}'s key to #{what}."
    else
      "D4H refuses the key to #{what}."
    end
  end

  defp ask_message(team, refused) do
    what = refused |> Enum.map(&String.downcase(&1.name)) |> Service.Format.and_list()

    "Can you make the D4H member #{team.d4h_access_key_owner} an Owner? SAR Duty uses " <>
      "its key, and D4H refuses it to #{what}."
  end

  def handle_event("check", _params, socket) do
    case CheckTeamKey.call(socket.assigns.current_team) do
      {:ok, team} ->
        {:noreply, socket |> assign_team(team) |> put_flash(:info, "Key checked.")}

      {:error, :refused} ->
        {:noreply, put_flash(socket, :error, "D4H refused the key. Save a new one below.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "D4H did not answer. Try again in a few minutes.")}
    end
  end

  def handle_event("save", %{"form" => form_params}, socket) do
    %{current_team: team, current_user: user} = socket.assigns

    case SaveTeamKey.call(team, form_params, user) do
      {:ok, team} ->
        socket =
          socket
          |> assign_team(team)
          |> assign_form(Team.build_key_changeset(team))
          |> put_flash(:info, "Key saved.")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end
end
