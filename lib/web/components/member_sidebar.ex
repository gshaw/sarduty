defmodule Web.Components.MemberSidebar do
  use Web, :function_component

  import Web.Components.A
  import Web.Components.D4H
  import Web.Components.CopyButton
  import Web.Components.OpenInMaps
  import Web.Components.Phone, only: [call_and_text: 1]

  alias App.Adapter.D4H
  alias Web.Components.NotAPersonSwitch
  alias Web.Components.OpenInMaps
  alias Web.Components.Phone

  attr :member, :map, required: true
  attr :maps_app, :string, default: "google", doc: "the account's maps_app"

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
        {Phone.format(@member.phone)}<.copy_button
          id="member-copy-phone"
          value={Phone.format(@member.phone)}
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
      <dd>
        {Service.Format.date_short(@member.joined_at, @member.team.timezone)} · {Service.Format.months_or_years_ago(
          @member.joined_at
        )} ago
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
    <.live_component module={NotAPersonSwitch} id="not-a-person" member={@member} />
    """
  end
end
