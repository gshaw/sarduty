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
  alias App.ViewData.EquipmentList
  alias App.ViewData.MemberMilestones
  alias Service.Format
  alias Web.Components.MilestoneList
  alias Web.Components.OpenInMaps
  alias Web.EquipmentCollectionLive

  @doc """
  Assigns the header's `last_attended_at` and `standing`, and the sidebar's
  `milestones` and `equipment`, for the socket's `member`. Call
  it when the member loads, not on every render: a form's change events re-render.
  """
  def load_sidebar(socket) do
    member = socket.assigns.member

    Phoenix.Component.assign(socket,
      last_attended_at: Member.last_attended_at(member),
      standing: MemberAwayPeriod.standing_today(member, member.team.timezone),
      milestones: MemberMilestones.for_member(member, DateTime.utc_now()),
      equipment: held(member)
    )
  end

  attr :member, :map, required: true
  attr :last_attended_at, :any, required: true, doc: "from load_sidebar/1"
  attr :standing, :any, required: true, doc: "from load_sidebar/1"
  attr :equipment, :list, required: true, doc: "from load_sidebar/1"

  @doc """
  The breadcrumbs and the member's name over every tab, with View as member: the same
  header Your membership opens with. A retired member's badge counts the items they still
  hold, the sidebar's Equipment list (#490).
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
      item_count={length(@equipment)}
      facts={facts(@member, @last_attended_at, @member.team.timezone)}
    >
      <:actions>
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

  attr :equipment, :list,
    required: true,
    doc: "the items the member holds, kits then their contents, from load_sidebar/1"

  # The header has the photo, role, joined, standing, and last attended, so the
  # sidebar is the member's ID, how to reach them, and D4H.
  def sidebar_content(assigns) do
    ~H"""
    <dl>
      <dt>ID</dt>
      <dd>{@member.ref_id}</dd>
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
      <%!-- Member pages are for team admins only, so no member sees another's (#423). --%>
      <dt>Emergency contact</dt>
      <.emergency_contact id="member-emergency" contact={@member.primary_emergency_contact} />
      <%= if shown?(@member.secondary_emergency_contact) do %>
        <dt>Second emergency contact</dt>
        <.emergency_contact id="member-emergency-2" contact={@member.secondary_emergency_contact} />
      <% end %>
      <%!-- What they hold, so a team admin sees what to get back (#490). --%>
      <%= if @equipment != [] do %>
        <dt>Equipment</dt>
        <.equipment_summary member={@member} equipment={@equipment} />
      <% end %>
      <%!-- The latest, and the rest on the team's Milestones page (#389). --%>
      <dt>Milestones</dt>
      <.milestones_summary member={@member} milestones={@milestones} />

      <%!-- A team on SAR Duty Records has no D4H to open, so it changes members here. --%>
      <dt>Actions</dt>
      <dd>
        <ul id="member-actions" class="action-list">
          <li :if={D4H.records?(@member.team)}>
            <.a id="member-edit" navigate={~p"/teams/#{@member.team}/members/#{@member.id}/edit"}>Change details</.a>
          </li>
          <li :if={!D4H.records?(@member.team)}>
            <.a external={true} href={D4H.member_url(@member)}>Open D4H member</.a>
          </li>
        </ul>
      </dd>
    </dl>
    """
  end

  @equipment_shown 5

  attr :member, :map, required: true
  attr :equipment, :list, required: true

  # Up to 5, since two teams issue full kits of up to 35 items, then the rest on Equipment.
  defp equipment_summary(assigns) do
    assigns =
      assign(assigns,
        shown: Enum.take(assigns.equipment, @equipment_shown),
        more?: length(assigns.equipment) > @equipment_shown
      )

    ~H"""
    <dd id="member-equipment">
      <ul class="list-none p-0 m-0">
        <li :for={row <- @shown} id={"member-equipment-#{row.item.id}"}>
          <.a navigate={~p"/teams/#{@member.team}/equipment/#{row.item.id}"}>{row.item.title}</.a>
          <span class="hint">{item_hint(row)}</span>
          <EquipmentCollectionLive.status_badge item={row.item} />
        </li>
      </ul>
      <ul :if={@more?} class="action-list">
        <li>
          <.a
            id="member-equipment-all"
            navigate={
              ~p"/teams/#{@member.team}/equipment?#{[place: EquipmentList.member_place(@member.id), show: "all"]}"
            }
          >{Format.count(length(@equipment), one: "%d item", many: "All %d items")}</.a>
        </li>
      </ul>
    </dd>
    """
  end

  @doc """
  The items `member` holds, as `EquipmentList.held_rows/1` gives them: each kit, then
  what's inside it.
  """
  def held(member),
    do: member.team |> EquipmentItem.held_by(member) |> EquipmentList.held_rows()

  @doc """
  What a held item's line says after its name: the kit it's in, \"In First aid kit 6\",
  so its contents read as part of it, or else its category and barcode, \"Radio · R-014\".
  """
  def item_hint(%{in: %{title: title}}), do: "In #{title}"

  def item_hint(%{item: item}) do
    [item.kind, item.barcode] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(" · ")
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
          {Service.Phone.format(phone)}<.copy_button
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
