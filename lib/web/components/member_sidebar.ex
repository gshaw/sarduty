defmodule Web.Components.MemberSidebar do
  use Web, :function_component

  import Web.Components.A
  import Web.Components.D4H

  alias App.Adapter.D4H
  alias Web.Components.NotAPersonSwitch

  attr :member, :map, required: true

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
        <.a href={"mailto:#{@member.email}"}>{@member.email}</.a>
      </dd>
      <dt>Phone</dt>
      <dd>
        <.a href={"tel:#{@member.phone}"}>{@member.phone}</.a>
      </dd>
      <dt>Address</dt>
      <dd>{@member.address}</dd>
      <dt>Joined</dt>
      <dd>
        {Service.Format.date_short(@member.joined_at, @member.team.timezone)} · {Service.Format.months_or_years_ago(
          @member.joined_at
        )} ago
      </dd>

      <%!-- A team on SAR Duty Records has no D4H to open. --%>
      <dt :if={!D4H.records?(@member.team)}>Actions</dt>
      <dd :if={!D4H.records?(@member.team)}>
        <ul class="action-list">
          <li>
            <.a external={true} href={D4H.member_url(@member)}>Open D4H member</.a>
          </li>
        </ul>
      </dd>
    </dl>
    <.live_component module={NotAPersonSwitch} id="not-a-person" member={@member} />
    """
  end
end
