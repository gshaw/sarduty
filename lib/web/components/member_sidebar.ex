defmodule Web.Components.MemberSidebar do
  use Web, :function_component

  import Web.Components.A
  import Web.Components.D4H

  alias App.Adapter.D4H

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
      <dd>{@member.email}</dd>
      <dt>Phone</dt>
      <dd>{@member.phone}</dd>
      <dt>Address</dt>
      <dd>{@member.address}</dd>
      <dt>Joined</dt>
      <dd>
        {Service.Format.long_date(@member.joined_at, @member.team.timezone)} ({Service.Format.duration_in_years(
          @member.joined_at,
          DateTime.utc_now()
        )} ago)
      </dd>

      <dt :if={@member.tax_credit_letters != []}>Tax Credit Letters</dt>
      <dd :if={@member.tax_credit_letters != []}>
        <ul class="action-list">
          <%= for letter <- Enum.sort_by(@member.tax_credit_letters, & &1.year, :desc) do %>
            <li>
              <.a navigate={~p"/#{@member.team.subdomain}/tax-credit-letters/#{letter.id}"}>
                {letter.year}
              </.a>
            </li>
          <% end %>
        </ul>
      </dd>

      <dt>Actions</dt>
      <dd>
        <ul class="action-list">
          <li>
            <.a external={true} href={D4H.member_url(@member)}>Open D4H Member</.a>
          </li>
        </ul>
      </dd>
    </dl>
    """
  end
end
