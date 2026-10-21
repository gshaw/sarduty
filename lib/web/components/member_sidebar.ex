defmodule Web.Components.MemberSidebar do
  use Web, :function_component

  import Web.Components.A
  import Web.Components.D4H
  import Web.Components.CopyButton
  import Web.Components.OpenInMaps
  import Web.Components.Phone, only: [call_and_text: 1]

  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Model.MemberAwayPeriod
  alias Web.Components.OpenInMaps

  attr :member, :map, required: true
  attr :maps_app, :string, default: "google", doc: "the account's maps_app"

  attr :last_attended_at, :any,
    required: true,
    doc: "when the member last attended an activity, from load_sidebar/1"

  attr :standing, :any, required: true, doc: "the member's standing today, from load_sidebar/1"

  @doc """
  Assigns the sidebar's `last_attended_at` and `standing` for the socket's `member`. Call
  it when the member loads, not on every render: a form's change events re-render.
  """
  def load_sidebar(socket) do
    member = socket.assigns.member

    Phoenix.Component.assign(socket,
      last_attended_at: Member.last_attended_at(member),
      standing: MemberAwayPeriod.standing_today(member, member.team.timezone)
    )
  end

  def sidebar_content(assigns) do
    ~H"""
    <dl>
      <p><.member_image member={@member} /></p>
      <dt>ID</dt>
      <dd>{@member.ref_id}</dd>
      <dt>Role</dt>
      <dd>{@member.position}</dd>
      <dt>Email</dt>
      <dd>
        <.a href={"mailto:#{@member.email}"}>{@member.email}</.a><.copy_button
          id="member-copy-email"
          value={@member.email}
          label="Copy email"
        />
      </dd>
      <dt>Phone</dt>
      <dd id="member-phone">
        {Service.Phone.format(@member.phone)}<.copy_button
          id="member-copy-phone"
          value={Service.Phone.format(@member.phone)}
          label="Copy phone number"
        />
        <.call_and_text id="member-phone" phone={@member.phone} class="mt-2" />
      </dd>
      <dt>Address</dt>
      <dd>
        {@member.address}<.copy_button
          id="member-copy-address"
          value={OpenInMaps.one_line(@member.address)}
          label="Copy address"
        />
        <%!-- No label: the member's name beside their address would leave SAR Duty. --%>
        <.open_in_maps id="member-maps" app={@maps_app} address={@member.address} />
      </dd>
      <dt>Joined</dt>
      <dd>{date_and_days_ago(@member.joined_at, @member.team.timezone)}</dd>
      <dt>Standing</dt>
      <dd id="member-standing">
        <.link navigate={~p"/teams/#{@member.team}/members/#{@member.id}/standing"} class="link">
          {Web.Components.Standing.text(@standing)}
        </.link>
      </dd>
      <dt>Last attended</dt>
      <dd id="member-last-attended">
        {last_attended(@last_attended_at, @member.team.timezone)}
      </dd>

      <%!-- A team on SAR Duty Records has no D4H to open, so it changes members here. --%>
      <dt>Actions</dt>
      <dd>
        <ul id="member-actions" class="action-list">
          <li :if={D4H.records?(@member.team)}>
            <.a id="member-edit" navigate={~p"/teams/#{@member.team}/members/#{@member.id}/edit"}>
              Change details
            </.a>
          </li>
          <li :if={!D4H.records?(@member.team)}>
            <.a external={true} href={D4H.member_url(@member)}>Open D4H member</.a>
          </li>
        </ul>
      </dd>
    </dl>
    """
  end

  defp last_attended(nil, _timezone), do: "Never"

  defp last_attended(started_at, timezone), do: date_and_days_ago(started_at, timezone)

  # "Oct 8, 2026 · 12 days ago"
  defp date_and_days_ago(datetime, timezone) do
    ago = Service.Format.days_ago(datetime, DateTime.utc_now(), timezone)
    "#{Service.Format.date_short(datetime, timezone)} · #{ago}"
  end
end
