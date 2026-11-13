defmodule Web.Components.FieldDefinitions do
  use Web, :function_component

  import Web.Components.RowLink

  alias App.Model.CustomField

  # What each custom field is (#872), on team settings' and organization settings' Fields
  # pages, never a value. The list is an index to scan, row links (#1056): the field's
  # name, its type in grey, at most one tag, and the first line of its hint, each bundle
  # under its title. Everything else is on the field's own page, in field_details/1. The
  # style guide's Field definitions page shows both.

  @activity_kinds ~w(incident exercise event)

  attr :id, :string, required: true
  attr :fields, :list, required: true, doc: "one target's fields, with their bundles preloaded"
  attr :path, :any, required: true, doc: "a function from a field to its own page"

  attr :team_name, :string,
    default: nil,
    doc: "on a team's page: its own fields come first, under its name, then its organization's"

  attr :organization_name, :string, default: nil, doc: "with team_name, the organization's"

  def field_list(assigns) do
    assigns = assign(assigns, :sections, sections(assigns))

    ~H"""
    <section :for={{key, heading, fields} <- @sections} id={"#{@id}-#{key}"} class="mb-8">
      <h2 :if={heading} class="heading mb-4">{heading}</h2>
      <div
        :for={{bundle, fields} <- CustomField.grouped(fields)}
        id={group_id(@id, key, bundle)}
        class="mb-6"
      >
        <h3 :if={bundle} class="subheading mb-2">{bundle.title}</h3>
        <ul class="row-links">
          <li :for={field <- fields} id={"field-#{field.id}"}>
            <.row_link navigate={@path.(field)}>
              <strong class="text-link">{field.title}</strong>
              <span class="hint">{about(field)}</span>
              <.field_tag field={field} />
              <span :if={first_line(field.hint)} class="hint block line-clamp-1">
                {first_line(field.hint)}
              </span>
            </.row_link>
          </li>
        </ul>
      </div>
    </section>
    """
  end

  # A team's own fields under its name, then its organization's. Without a team name,
  # one section with no heading: an organization's page lists only its own.
  defp sections(%{team_name: nil, fields: fields}), do: [{"all", nil, fields}]

  defp sections(%{team_name: team_name, organization_name: organization_name, fields: fields}) do
    {organization, own} = Enum.split_with(fields, &CustomField.organisation?/1)

    [
      {"team", "#{team_name}'s fields", own},
      {"organization", "#{organization_name || "Your organization"}'s fields", organization}
    ]
    |> Enum.reject(&(elem(&1, 2) == []))
  end

  defp group_id(id, key, nil), do: "#{id}-#{key}-fields"
  defp group_id(id, key, bundle), do: "#{id}-#{key}-bundle-#{bundle.d4h_bundle_id}"

  # The type, and on a member field who sees it: "Text · Members see their own".
  defp about(%CustomField{target: "member"} = field),
    do: "#{CustomField.type_label(field.field_type)} · #{members_short(field.member_privacy)}"

  defp about(field), do: CustomField.type_label(field.field_type)

  defp members_short("viewable"), do: "Members see their own"
  defp members_short("editable"), do: "Members change their own"
  defp members_short(_hidden), do: "Team admins only"

  attr :field, CustomField, required: true

  # At most one tag: Needed to publish on an activity field, else Restricted on an
  # activity or equipment field. Restricted changes nothing on a member field.
  defp field_tag(%{field: %{target: target, required: true}} = assigns)
       when target in @activity_kinds do
    ~H"""
    <.badge kind={:primary}>Needed to publish</.badge>
    """
  end

  defp field_tag(%{field: %{target: target, restricted: true}} = assigns)
       when target != "member" do
    ~H"""
    <.badge>Restricted</.badge>
    """
  end

  defp field_tag(assigns), do: ~H""

  defp first_line(nil), do: nil

  defp first_line(hint) do
    case hint |> String.split("\n", trim: true) |> Enum.map(&String.trim/1) do
      [line | _] when line != "" -> line
      _blank -> nil
    end
  end

  attr :field, CustomField, required: true, doc: "with its bundle preloaded"
  attr :timezone, :string, required: true

  attr :team_names, :map,
    required: true,
    doc: ~s(who added a team's field or choice, by the team's D4H id: %{11 => "Coast Range SAR"})

  attr :organization_name, :string,
    default: nil,
    doc: "who added an organization's field: D4H names it by an id SAR Duty doesn't keep"

  attr :team_name, :string,
    default: nil,
    doc: "the team whose page this is; nil on an organization's page"

  attr :service, :string, default: "D4H", doc: "where the field changes: D4H.service_name/1"
  attr :restricted_text, :string, default: nil, doc: "what a RESTRICTED field means here"

  @doc """
  One field on its own page (#1056), a detail list in one order, leaving out what a field
  lacks: what it means, its type, what it's on, who added it, needed to publish, what
  members see, restricted, and its choices, with the ones a team added and the archived
  ones apart. Each setting carries a line on what it means.
  """
  def field_details(assigns) do
    names = {assigns.team_names, assigns.organization_name}
    {own, added, archived} = split_options(assigns.field)

    assigns =
      assign(assigns,
        names: names,
        org: assigns.organization_name || "Your organization",
        own: own,
        added:
          added |> Enum.group_by(&owner_name(names, owner(&1))) |> Enum.sort_by(&elem(&1, 0)),
        archived: archived
      )

    ~H"""
    <dl id="field-details" class="measure">
      <div :if={@field.hint not in [nil, ""]} id="field-hint">
        <dt>What it means</dt>
        <dd>{@field.hint}</dd>
      </div>
      <div id="field-type">
        <dt>Type</dt>
        <dd>
          {CustomField.type_label(@field.field_type)}<span :if={@field.value_units}>, in {@field.value_units}</span>
        </dd>
      </div>
      <div id="field-on">
        <dt>On</dt>
        <dd>
          {CustomField.target_title(@field.target)}<span :if={@field.bundle}>, under {@field.bundle.title}</span>
        </dd>
      </div>
      <div id="field-from">
        <dt>Added by</dt>
        <dd>
          {owner_name(@names, owner(@field))}<span :if={@field.d4h_created_at}>, {Service.Format.date_short(
            @field.d4h_created_at,
            @timezone
          )}</span>
          <span class="hint block">{added_by_text(@field, @org, @team_name, @service)}</span>
        </dd>
      </div>
      <div :if={@field.required and @field.target in ~w(incident exercise event)} id="field-required">
        <dt>Needed to publish</dt>
        <dd>
          Yes <span class="hint block">{required_text(@field.target)}</span>
        </dd>
      </div>
      <div :if={@field.target == "member"} id="field-members">
        <dt>Members</dt>
        <dd>
          {members_text(@field.member_privacy)}
          <span class="hint block">
            {if @team_name, do: "Team admins", else: "Each team's admins"} see every member's answer. Change this setting in {@service}.
          </span>
        </dd>
      </div>
      <div :if={@field.restricted and @restricted_text} id="field-restricted">
        <dt>Restricted</dt>
        <dd>
          Yes <span class="hint block">{@restricted_text}</span>
        </dd>
      </div>
      <div :if={@own != []} id="field-choices">
        <dt>Choices</dt>
        <dd>
          <ul class="list-disc pl-6">
            <li :for={option <- @own}>{option["label"]}</li>
          </ul>
        </dd>
      </div>
      <div :for={{name, options} <- @added} id={"field-added-#{slug(name)}"}>
        <dt>{name} added</dt>
        <dd>
          <ul class="list-disc pl-6">
            <li :for={option <- options}>{option["label"]}</li>
          </ul>
          <span :if={name == @team_name} class="hint block">
            Your team added these choices. Only {@org} can change the rest of the field.
          </span>
        </dd>
      </div>
      <div :if={@archived != []} id="field-archived-choices">
        <dt>Archived choices</dt>
        <dd>
          <ul class="list-disc pl-6">
            <li :for={option <- @archived}>{option["label"]}</li>
          </ul>
        </dd>
      </div>
    </dl>
    """
  end

  # Why an organization has a field, and who can change it.
  defp added_by_text(%CustomField{owner_type: "Organisation"}, org, team_name, service) do
    why =
      "Every #{org} team has this field, so #{org}'s reports read it the same way on each team."

    if team_name, do: "#{why} Only #{org} can change it.", else: "#{why} Change it in #{service}."
  end

  defp added_by_text(_field, _org, _team_name, service),
    do: "Only your team has this field. Change it in #{service}."

  defp required_text("incident"),
    do:
      "Fill it in before you publish the incident. SAR Duty marks it Missing on a draft incident."

  defp required_text(kind), do: "Fill it in before you publish the #{kind}."

  defp members_text("viewable"), do: "Each member sees their own answer."
  defp members_text("editable"), do: "Each member sees their own answer and can change it."
  defp members_text(_hidden), do: "Members don't see their own answer."

  defp slug(name), do: name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-")

  # A team's name, or the organization's. Every Organisation owner is the team's
  # organization, since D4H gives a team only its own organization's fields.
  defp owner_name({team_names, _organization}, {"Team", id}),
    do: Map.get(team_names, id, "A team")

  defp owner_name({_team_names, organization}, _owner), do: organization || "Your organization"

  # The field's live choices from whoever added the field, the live ones a team added to
  # an organization's field, and the archived ones, each in D4H's order. A choice with no
  # owner is the field's own.
  defp split_options(field) do
    {live, archived} =
      field.options |> Enum.sort_by(& &1["ordering"]) |> Enum.split_with(&(not &1["archived"]))

    {own, added} = Enum.split_with(live, &(owner(&1) in [owner(field), {nil, nil}]))
    {own, added, archived}
  end

  defp owner(%CustomField{owner_type: type, owner_id: id}), do: {type, id}
  defp owner(option), do: {option["owner_type"], option["owner_id"]}
end
