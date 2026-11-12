defmodule Web.Components.FieldDefinitions do
  use Web, :function_component

  import Web.Components.Columns, only: [date_cell: 1, date_fit: 1]
  import Web.Components.Table

  alias App.Model.CustomField

  # What each custom field is (#872), on team settings' and organization settings' Fields
  # pages: its title, hint, and choices, its type, who added it, and when. Never a value.
  # One table per bundle, each bundle's title over its own, with the same column widths
  # so they line up down the page. The style guide's Field definitions page shows it.

  attr :id, :string, required: true
  attr :fields, :list, required: true, doc: "one target's fields, with their bundles preloaded"
  attr :timezone, :string, required: true

  attr :team_names, :map,
    required: true,
    doc: ~s(who added a team's field or choice, by the team's D4H id: %{11 => "Coast Range SAR"})

  attr :organization_name, :string,
    default: nil,
    doc: "who added an organization's field: D4H names it by an id SAR Duty doesn't keep"

  attr :from?, :boolean, default: true, doc: "a From column naming who added each field"

  attr :publish?, :boolean,
    default: false,
    doc: "an activity's: a required one says Needed to publish"

  attr :restricted_text, :string,
    default: nil,
    doc: "what a RESTRICTED field says about its values"

  attr :copy?, :boolean,
    default: false,
    doc: "member fields: who sees them, and a Copy check box named `fields[]`, or Stays private"

  def field_definitions(assigns) do
    names = {assigns.team_names, assigns.organization_name}

    assigns =
      assign(assigns,
        names: names,
        groups: CustomField.grouped(assigns.fields),
        added_fit: date_fit(assigns.timezone),
        from_fit:
          Enum.uniq([owner_name(names, {"Organisation", nil}) | Map.values(assigns.team_names)])
      )

    ~H"""
    <div :for={{bundle, fields} <- @groups} id={group_id(@id, bundle)} class="mb-6">
      <h3 :if={bundle} class="subheading mb-2">{bundle.title}</h3>
      <.table id={"#{group_id(@id, bundle)}-table"} rows={fields} row_id={&"field-#{&1.id}"}>
        <:col :let={field} label="Field">
          {field.title}
          <span :if={@publish? and field.required} class="ml-2"><.badge>Needed to publish</.badge></span>
          <%= for line <- about(field, @names, @restricted_text) do %>
            <span :if={is_binary(line)} class="hint block">{line}</span>
            <details :if={is_map(line)} class="hint">
              <summary>
                {line.label}: {Enum.join(line.first, ", ")}, {more_text(
                  length(line.all) - length(line.first)
                )}
              </summary>
              <ul class="list-disc pl-6">
                <li :for={label <- line.all}>{label}</li>
              </ul>
            </details>
          <% end %>
        </:col>
        <:col :let={field} label="Type" fit={["Date and time", "Long text", "One choice"]}>
          {CustomField.type_label(field.field_type)}
        </:col>
        <:col :let={field} :if={@from?} label="From" fit={@from_fit}>
          {owner_name(@names, owner(field))}
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
        <:col :let={field} label="Added" fit={@added_fit}>
          <.date_cell value={field.d4h_created_at} timezone={@timezone} />
        </:col>
      </.table>
    </div>
    """
  end

  defp group_id(id, nil), do: "#{id}-fields"
  defp group_id(id, bundle), do: "#{id}-bundle-#{bundle.d4h_bundle_id}"

  # A team's name, or the organization's. Every Organisation owner is the team's
  # organization, since D4H gives a team only its own organization's fields.
  defp owner_name({team_names, _organization}, {"Team", id}),
    do: Map.get(team_names, id, "A team")

  defp owner_name({_team_names, organization}, _owner), do: organization || "Your organization"

  @doc """
  The lines under a field's title: its hint, its choices, the choices each team added to
  an organization's field, its archived choices, and what a RESTRICTED one means. `names`
  is `{team_names, organization_name}`. A list of more than 8 choices is a map,
  `%{label:, first:, all:}`: the page shows its first 3 and a count that opens the rest.
  """
  def about(field, names, restricted_text) do
    {own, added, archived} = split_options(field)

    [
      field.hint,
      choices_line("Choices", own),
      added_lines(added, names),
      choices_line("Archived choices", archived),
      field.restricted && restricted_text
    ]
    |> List.flatten()
    |> Enum.filter(&(is_map(&1) or (is_binary(&1) and &1 != "")))
  end

  @short 8
  @first 3

  defp more_text(count), do: Service.Format.count(count, one: "and %d more", many: "and %d more")

  # The field's live choices from whoever added the field, the live ones a team added to
  # an organization's field, and the archived ones, each in D4H's order. A choice with no
  # owner is the field's own.
  defp split_options(field) do
    {live, archived} =
      field.options |> Enum.sort_by(& &1["ordering"]) |> Enum.split_with(&(not &1["archived"]))

    {own, added} = Enum.split_with(live, &(owner(&1) in [owner(field), {nil, nil}]))
    {own, added, archived}
  end

  defp choices_line(_label, []), do: nil

  defp choices_line(label, options) when length(options) <= @short,
    do: "#{label}: #{labels(options)}."

  defp choices_line(label, options) do
    all = Enum.map(options, & &1["label"])
    %{label: label, first: Enum.take(all, @first), all: all}
  end

  # One line per team that added choices to an organization's field, by team name.
  defp added_lines(options, names) do
    options
    |> Enum.group_by(&owner_name(names, owner(&1)))
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {name, options} -> choices_line("#{name} added", options) end)
  end

  defp owner(%CustomField{owner_type: type, owner_id: id}), do: {type, id}
  defp owner(option), do: {option["owner_type"], option["owner_id"]}

  defp labels(options), do: Enum.map_join(options, ", ", & &1["label"])
end
