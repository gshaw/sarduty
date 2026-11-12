defmodule Web.Components.FieldDefinitions do
  use Web, :function_component

  import Web.Components.A
  import Web.Components.Table

  alias App.Model.CustomField

  # What each custom field is (#872), on team settings' and organization settings' Fields
  # pages, never a value. The list is an index to scan: one line per field, its name and
  # the first line of its hint, each bundle under its title. Everything else, its type,
  # choices, who added it, and when, is on the field's own page, in field_details/1. The
  # style guide's Field definitions page shows both.

  attr :id, :string, required: true
  attr :fields, :list, required: true, doc: "one target's fields, with their bundles preloaded"
  attr :path, :any, required: true, doc: "a function from a field to its own page"

  attr :publish?, :boolean,
    default: false,
    doc: "an activity's: a required one says Needed to publish"

  attr :copy?, :boolean,
    default: false,
    doc: "member fields: who sees them, and a Copy check box named `fields[]`, or Stays private"

  def field_list(assigns) do
    assigns = assign(assigns, :groups, CustomField.grouped(assigns.fields))

    ~H"""
    <div :for={{bundle, fields} <- @groups} id={group_id(@id, bundle)} class="mb-6">
      <h3 :if={bundle} class="subheading mb-2">{bundle.title}</h3>
      <.table id={"#{group_id(@id, bundle)}-table"} rows={fields} row_id={&"field-#{&1.id}"}>
        <:col :let={field} label="Field" class="w-1/3">
          <.a navigate={@path.(field)}>{field.title}</.a>
        </:col>
        <:col :let={field} label="What it means">
          <span class="hint line-clamp-1">{field.hint}</span>
        </:col>
        <:col :let={field} :if={@publish?} label="Needed" fit={["Needed to publish"]}>
          <.badge :if={field.required}>Needed to publish</.badge>
        </:col>
        <:col :let={field} :if={@copy?} label="Members" fit={["Change their own", "See their own"]}>
          {CustomField.member_privacy_label(field.member_privacy)}
        </:col>
        <:col :let={field} :if={@copy?} label="Copy" fit={["Stays private"]}>
          <span :if={field.restricted} id={"member-field-#{field.d4h_custom_field_id}-private"}>
            Stays private
          </span>
          <input
            :if={!field.restricted}
            type="checkbox"
            id={"member-field-#{field.d4h_custom_field_id}"}
            name="fields[]"
            value={field.d4h_custom_field_id}
            checked={field.copy_values}
            aria-label={"Copy #{field.title}"}
          />
        </:col>
      </.table>
    </div>
    """
  end

  defp group_id(id, nil), do: "#{id}-fields"
  defp group_id(id, bundle), do: "#{id}-bundle-#{bundle.d4h_bundle_id}"

  attr :field, CustomField, required: true, doc: "with its bundle preloaded"
  attr :timezone, :string, required: true

  attr :team_names, :map,
    required: true,
    doc: ~s(who added a team's field or choice, by the team's D4H id: %{11 => "Coast Range SAR"})

  attr :organization_name, :string,
    default: nil,
    doc: "who added an organization's field: D4H names it by an id SAR Duty doesn't keep"

  attr :restricted_text, :string, default: nil, doc: "what a RESTRICTED field says"

  @doc """
  One field on its own page: what it means, its type, what it's on, who added it and
  when, and every choice, one per line, with the ones a team added and the archived ones
  apart.
  """
  def field_details(assigns) do
    names = {assigns.team_names, assigns.organization_name}
    {own, added, archived} = split_options(assigns.field)

    assigns =
      assign(assigns,
        names: names,
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
          {CustomField.type_label(@field.field_type)}
          <span :if={@field.value_units}>, in {@field.value_units}</span>
          <span :if={@field.required and @field.target in ~w(incident exercise event)} class="ml-2">
            <.badge>Needed to publish</.badge>
          </span>
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
        </dd>
      </div>
      <div :if={@field.target == "member"} id="field-members">
        <dt>Members</dt>
        <dd>{CustomField.member_privacy_label(@field.member_privacy)}</dd>
      </div>
      <div :if={@field.restricted and @restricted_text} id="field-restricted">
        <dt>Restricted</dt>
        <dd>{@restricted_text}</dd>
      </div>
      <div :if={@own != []} id="field-choices">
        <dt>Choices</dt>
        <dd>
          <ul class="list-disc pl-6">
            <li :for={option <- @own}>{option["label"]}</li>
          </ul>
        </dd>
      </div>
      <div :for={{name, options} <- @added}>
        <dt>{name} added</dt>
        <dd>
          <ul class="list-disc pl-6">
            <li :for={option <- options}>{option["label"]}</li>
          </ul>
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
