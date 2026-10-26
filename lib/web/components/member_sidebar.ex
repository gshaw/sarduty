defmodule Web.Components.MemberSidebar do
  use Web, :function_component

  import Web.Components.A
  import Web.Components.Breadcrumbs
  import Web.Components.CopyButton
  import Web.Components.OpenInMaps
  import Web.Components.PersonHead
  import Web.Components.Phone, only: [call_and_text: 1]

  alias App.Adapter.D4H
  alias App.Model.EquipmentItem
  alias App.Model.Member
  alias App.Model.MemberAwayPeriod
  alias App.ViewData.MemberMilestones
  alias Service.Format
  alias Web.Components.MilestoneList
  alias Web.Components.OpenInMaps

  @doc """
  Assigns the header's `last_attended_at` and `standing`, as the viewer sees it, the
  sidebar's `milestones`, and the `equipment` that decides whether the tabs show
  Equipment, for the socket's `member`. Call it when the member loads, not on every
  render: a form's change events re-render.
  """
  def load_sidebar(socket) do
    %{member: member, team_admin?: team_admin?} = socket.assigns
    standing = MemberAwayPeriod.standing_today(member, member.team.timezone)

    Phoenix.Component.assign(socket,
      last_attended_at: Member.last_attended_at(member),
      standing: MemberAwayPeriod.visible_standing(standing, team_admin?),
      milestones: MemberMilestones.for_member(member, DateTime.utc_now()),
      equipment: EquipmentItem.held_by(member.team, member)
    )
  end

  attr :member, :map, required: true
  attr :last_attended_at, :any, required: true, doc: "from load_sidebar/1"
  attr :standing, :any, required: true, doc: "from load_sidebar/1"
  attr :team_admin?, :boolean, default: false, doc: "adds View as member"

  @doc """
  The breadcrumbs and the member's name over every tab, with View as member for a team
  admin: the same header Your membership opens with.
  """
  def member_head(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Members" path={~p"/teams/#{@member.team}/members/"} />
      <:item label={@member.name} />
    </.breadcrumbs>
    <.person_head
      id="member-head"
      class="mb-6"
      name={@member.name}
      photo={~p"/teams/#{@member.team}/members/#{@member.id}/image"}
      standing={@standing}
      facts={facts(@member, @last_attended_at, @member.team.timezone)}
    >
      <:actions :if={@team_admin?}>
        <.button
          id="view-as"
          href={~p"/teams/#{@member.team}/members/#{@member.id}/view-as"}
          method="post"
        >
          View as member
        </.button>
      </:actions>
    </.person_head>
    """
  end

  attr :member, :map, required: true
  attr :maps_app, :string, default: "google", doc: "the account's maps_app"

  attr :milestones, :list,
    required: true,
    doc: "the member's milestones, newest first, from load_sidebar/1"

  attr :team_admin?, :boolean, default: false, doc: "adds contact details and Actions"

  # The header has the photo, role, joined, standing, and last attended, so the
  # sidebar is the member's ID, how to reach them, and D4H. Members see the ID and
  # milestones: other members' contact details stay with team admins (#440).
  def sidebar_content(assigns) do
    ~H"""
    <dl>
      <dt>ID</dt>
      <dd>{@member.ref_id}</dd>
      <.contact_details :if={@team_admin?} member={@member} maps_app={@maps_app} />
      <%!-- The latest, and the rest on the team's Milestones page (#389). --%>
      <dt>Milestones</dt>
      <.milestones_summary member={@member} milestones={@milestones} />

      <.member_actions :if={@team_admin?} member={@member} />
    </dl>
    """
  end

  attr :member, :map, required: true

  # A team on SAR Duty Records has no D4H to open, so it changes members here.
  defp member_actions(assigns) do
    ~H"""
    <dt>Actions</dt>
    <dd>
      <ul id="member-actions" class="action-list">
        <li :if={D4H.records?(@member.team)}>
          <.a id="member-edit" navigate={~p"/teams/#{@member.team}/members/#{@member.id}/edit"}>Change details</.a>
        </li>
        <li :if={!D4H.records?(@member.team)}>
          <.a external={true} href={D4H.member_url(@member)}>Open {D4H.service_name(@member.team)} member</.a>
        </li>
      </ul>
    </dd>
    """
  end

  attr :member, :map, required: true
  attr :maps_app, :string, required: true

  defp contact_details(assigns) do
    ~H"""
    <dt>Email</dt>
    <dd>
      <.copy_button
        text={@member.email}
        href={"mailto:#{@member.email}"}
        id="member-copy-email"
        value={@member.email}
        label="Copy email"
      />
    </dd>
    <dt>Phone</dt>
    <dd id="member-phone">
      <.copy_button
        text={Service.Phone.format(@member.phone)}
        id="member-copy-phone"
        value={Service.Phone.format(@member.phone)}
        label="Copy phone number"
      />
      <.call_and_text id="member-phone" phone={@member.phone} class="mt-2" />
    </dd>
    <dt>Address</dt>
    <dd>
      <.copy_button
        text={@member.address}
        id="member-copy-address"
        value={OpenInMaps.one_line(@member.address)}
        label="Copy address"
      />
      <%!-- No label: the member's name beside their address would leave SAR Duty. --%>
      <.open_in_maps id="member-maps" app={@maps_app} address={@member.address} />
    </dd>
    <%!-- Team admins only, so no member sees another's (#423). --%>
    <dt>Emergency contact</dt>
    <.emergency_contact id="member-emergency" contact={@member.primary_emergency_contact} />
    <%= if shown?(@member.secondary_emergency_contact) do %>
      <dt>Second emergency contact</dt>
      <.emergency_contact id="member-emergency-2" contact={@member.secondary_emergency_contact} />
    <% end %>
    """
  end

  attr :member, :map, required: true
  attr :milestones, :list, required: true

  defp milestones_summary(%{milestones: []} = assigns) do
    ~H"""
    <dd id="member-milestones">None</dd>
    """
  end

  defp milestones_summary(assigns) do
    assigns = assign(assigns, :latest, hd(assigns.milestones))

    ~H"""
    <dd id="member-milestones">
      {MilestoneList.title(@latest)} · {Format.date_long(@latest.on)}
      <ul :if={length(@milestones) > 1} class="action-list">
        <li>
          <.a
            id="member-milestones-all"
            navigate={~p"/teams/#{@member.team}/milestones?member=#{@member.id}&when=all"}
          >{Format.count(length(@milestones), one: "%d milestone", many: "All %d milestones")}</.a>
        </li>
      </ul>
    </dd>
    """
  end

  attr :id, :string, required: true
  attr :contact, :map, default: nil, doc: "a member's emergency contact, maybe nil"

  defp emergency_contact(assigns) do
    ~H"""
    <dd id={@id}>
      <%= if shown?(@contact) do %>
        {contact_name(@contact)}
        <span :for={{phone, i} <- Enum.with_index(phones(@contact))} class="block">
          <.copy_button
            text={Service.Phone.format(phone)}
            id={"#{@id}-copy-#{i}"}
            value={Service.Phone.format(phone)}
            label="Copy phone number"
          />
        </span>
        <.call_and_text
          :if={present?(@contact["primary_phone"])}
          id={@id}
          phone={@contact["primary_phone"]}
          class="mt-2"
        />
      <% else %>
        None
      <% end %>
    </dd>
    """
  end

  @doc "Whether an emergency contact has a name or a phone, so there is something to show."
  def shown?(contact),
    do: is_map(contact) and (present?(contact["name"]) or phones(contact) != [])

  defp present?(value), do: value not in [nil, ""]

  @doc ~S|"Sam Lee (Partner)", or just the name or the relation when that is all D4H has.|
  def contact_name(contact) do
    {name, relation} = {contact["name"], contact["relation"]}

    cond do
      present?(name) and present?(relation) -> "#{name} (#{relation})"
      present?(name) -> name
      true -> relation
    end
  end

  @doc "An emergency contact's phone numbers, as D4H has them."
  def phones(contact),
    do: Enum.filter([contact["primary_phone"], contact["secondary_phone"]], &present?/1)
end
