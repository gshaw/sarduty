defmodule Web.Components.CustomFields do
  use Phoenix.Component

  import Web.Components.Core

  alias App.Model.CustomField

  # A record's D4H custom fields (#681): a table on the record's Fields tab, from
  # App.Model.CustomField.rows/4, and the inputs on a Change fields page. A required field
  # with no value says Missing. Both group their fields by D4H's bundles (#872), each
  # bundle's title over its fields, after the fields in none: CustomField.grouped/2. The
  # style guide's Detail list page shows them.

  attr :id, :string, required: true
  attr :rows, :list, required: true

  attr :required, :integer,
    default: 0,
    doc: "how many of the fields D4H needs to publish, for the count over the missing ones"

  attr :fields_path, :string,
    default: nil,
    doc: "the team's Fields page in settings, linked when nothing is filled in; team admins only"

  @doc """
  A record's Fields tab: a table of each field and its value. The missing ones come
  first, under a count, in one list so the required ones aren't spread across headings.
  Then the rest in D4H's order, each bundle under its title.
  """
  def custom_fields_table(assigns) do
    {missing, filled} = Enum.split_with(assigns.rows, & &1.missing?)
    groups = CustomField.grouped(filled, & &1.field)
    assigns = assign(assigns, missing: missing, groups: groups)

    ~H"""
    <section id={@id}>
      <div :if={@missing != []} class="mb-8">
        <p id={"#{@id}-missing-count"} class="mb-4">
          {missing_text({length(@missing), @required})}
        </p>
        <.fields_table id={"#{@id}-missing"} prefix={@id} rows={@missing} />
      </div>
      <div :for={{{bundle, rows}, index} <- Enum.with_index(@groups)} class={index > 0 && "mt-8"}>
        <h2 :if={bundle} class="heading">{bundle.title}</h2>
        <.fields_table id={table_id(@id, bundle)} prefix={@id} rows={rows} />
      </div>
      <p :if={@rows == []} class="hint">
        No fields filled in.
        <.link :if={@fields_path} id={"#{@id}-meanings"} navigate={@fields_path}>
          What each field means
        </.link>
      </p>
    </section>
    """
  end

  defp table_id(id, nil), do: "#{id}-filled"
  defp table_id(id, bundle), do: "#{id}-bundle-#{bundle.d4h_bundle_id}"

  attr :id, :string, required: true
  attr :prefix, :string, required: true, doc: "each row's id starts with it"
  attr :rows, :list, required: true

  defp fields_table(assigns) do
    ~H"""
    <div class="table-wrap">
      <table id={@id} class="table table-striped table-fields">
        <tbody>
          <tr :for={row <- @rows} id={"#{@prefix}-#{row.field.d4h_custom_field_id}"}>
            <th scope="row">{row.field.title}</th>
            <td :if={!row.missing?}>{row.text}</td>
            <td :if={row.missing?}>
              <.badge kind={:warning}>Missing</.badge>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :fields, :list, required: true
  attr :values, :map, required: true, doc: "the record's custom_values, by D4H field id"

  attr :publish?, :boolean,
    default: false,
    doc: "an activity's fields: a required one is tagged Needed to publish"

  attr :flag_missing?, :boolean,
    default: false,
    doc: "a draft incident's: a required one left empty is tagged Missing"

  attr :bundle_tag, :string,
    default: "h2",
    doc:
      "each bundle's heading, h3 under a section's own h2 such as Change fields' on Your membership"

  attr :read_only, :list,
    default: [],
    doc: "local ids of fields shown as their value in place, such as one a member only sees"

  attr :timezone, :string, default: "Etc/UTC", doc: "the team's, for a read-only date"

  @doc """
  A record's fields as inputs on its Change fields page (#705), each as its type's input,
  named `fields[<D4H field id>]`, each bundle's under its title. On an activity a
  required one is tagged Needed to publish, and on a draft incident one left empty is
  tagged Missing, with an amber bar. Never an error: D4H saves them blank and checks them
  only when it publishes.
  """
  def custom_field_inputs(assigns) do
    assigns = assign(assigns, :groups, CustomField.grouped(assigns.fields))

    ~H"""
    <%= for {{bundle, fields}, index} <- Enum.with_index(@groups) do %>
      <.dynamic_tag
        :if={bundle}
        tag_name={@bundle_tag}
        id={"custom-field-bundle-#{bundle.d4h_bundle_id}"}
        class={[if(@bundle_tag == "h2", do: "heading", else: "subheading"), index > 0 && "mt-8"]}
      >
        {bundle.title}
      </.dynamic_tag>
      <%= for field <- fields do %>
        <.read_only_field
          :if={field.id in @read_only}
          field={field}
          value={@values[Integer.to_string(field.d4h_custom_field_id)]}
          timezone={@timezone}
        />
        <.custom_input
          :if={field.id not in @read_only}
          field={field}
          value={form_value(@values[Integer.to_string(field.d4h_custom_field_id)])}
          mark={mark(field, @values, @publish?, @flag_missing?)}
        />
      <% end %>
    <% end %>
    """
  end

  attr :field, CustomField, required: true
  attr :value, :any, required: true
  attr :timezone, :string, required: true

  # A field among the inputs that can't be changed here: its value, or None.
  defp read_only_field(assigns) do
    ~H"""
    <dl class="mb-6">
      <div id={"own-fields-#{@field.d4h_custom_field_id}"}>
        <dt>{@field.title}</dt>
        <dd>
          {if @value in [nil, "", []],
            do: "None",
            else: CustomField.display(@field, @value, @timezone)}
        </dd>
      </div>
    </dl>
    """
  end

  defp mark(field, values, publish?, flag_missing?) do
    cond do
      not (publish? and field.required) -> nil
      flag_missing? and empty?(values[Integer.to_string(field.d4h_custom_field_id)]) -> :missing
      true -> :needed
    end
  end

  @doc """
  How many of `fields` D4H needs to publish are empty in `values`, the record's or what
  the form holds now, as `{missing, required}` for missing_text/1.
  """
  def missing_count(fields, values) do
    required = Enum.filter(fields, & &1.required)

    {Enum.count(required, &empty?(values[Integer.to_string(&1.d4h_custom_field_id)])),
     length(required)}
  end

  # The form sends an empty box as "", and boxes to tick with a blank first.
  defp empty?(value) when is_list(value), do: Enum.all?(value, &empty?/1)
  defp empty?(value), do: value in [nil, ""]

  # Option ids as the inputs send them back, as strings.
  defp form_value(list) when is_list(list), do: Enum.map(list, &to_string/1)
  defp form_value(value), do: value

  @doc """
  The count over a record's missing fields, from `{missing, required}`: "9 of 19 needed
  to publish are empty."
  """
  def missing_text({missing, required}) do
    Service.Format.count(missing,
      one: "%d of #{required} needed to publish is empty.",
      many: "%d of #{required} needed to publish are empty."
    )
  end

  attr :field, CustomField, required: true
  attr :value, :any, default: nil
  attr :mark, :atom, values: [nil, :needed, :missing], required: true

  defp custom_input(%{field: %{field_type: "multiple_choice"}} = assigns) do
    assigns =
      assign(assigns, id: input_id(assigns.field), name: input_name(assigns.field) <> "[]")

    ~H"""
    <fieldset id={@id} class={["mb-6", @mark == :missing && "field-missing"]}>
      <legend>{@field.title}<.mark mark={@mark} /></legend>
      <.hint :if={@field.hint not in [nil, ""]}>{@field.hint}</.hint>
      <input type="hidden" name={@name} value="" />
      <label :for={{label, value} <- options(@field, @value)} class="choice">
        <input
          type="checkbox"
          id={"#{@id}-#{value}"}
          name={@name}
          value={value}
          checked={value in List.wrap(@value)}
        />
        {label}
      </label>
    </fieldset>
    """
  end

  defp custom_input(%{field: %{field_type: "single_choice"}} = assigns) do
    assigns =
      assign(assigns,
        id: input_id(assigns.field),
        name: input_name(assigns.field),
        options: options(assigns.field, assigns.value),
        selected: assigns.value |> List.wrap() |> List.first()
      )

    ~H"""
    <.input
      id={@id}
      name={@name}
      type={if length(@options) > 10, do: "combobox", else: "select"}
      label={@field.title}
      field_class={@mark == :missing && "field-missing"}
      prompt="None"
      clearable
      options={@options}
      value={@selected}
    >
      <:label_end><.mark mark={@mark} /></:label_end>
      {@field.hint}
    </.input>
    """
  end

  defp custom_input(assigns) do
    assigns =
      assign(assigns,
        id: input_id(assigns.field),
        name: input_name(assigns.field),
        type: input_type(assigns.field.field_type),
        shown: shown_value(assigns.field.field_type, assigns.value)
      )

    ~H"""
    <.input
      id={@id}
      name={@name}
      type={@type}
      label={@field.title}
      field_class={@mark == :missing && "field-missing"}
      value={@shown}
      rows={@type == "textarea" && "3"}
      step={@type == "number" && "any"}
    >
      <:label_end><.mark mark={@mark} /></:label_end>
      {@field.hint}
    </.input>
    """
  end

  defp input_id(field), do: "custom-field-#{field.d4h_custom_field_id}"
  defp input_name(field), do: "fields[#{field.d4h_custom_field_id}]"

  defp input_type("text_area"), do: "textarea"
  defp input_type("number"), do: "number"
  defp input_type("date"), do: "date"
  defp input_type("time"), do: "time"
  defp input_type(_text_or_datetime), do: "text"

  defp shown_value("date", value) when is_binary(value), do: String.slice(value, 0, 10)
  defp shown_value(_type, value), do: value

  attr :mark, :atom, required: true

  defp mark(%{mark: nil} = assigns), do: ~H""

  defp mark(assigns) do
    ~H"""
    <span class="ml-2">
      <.badge :if={@mark == :missing} kind={:warning}>Missing</.badge>
      <.badge :if={@mark == :needed}>Needed to publish</.badge>
    </span>
    """
  end

  # The live options in D4H's order, and an archived one only while it is chosen.
  defp options(field, value) do
    chosen = value |> List.wrap() |> Enum.map(&to_string/1)

    field.options
    |> Enum.sort_by(& &1["ordering"])
    |> Enum.filter(&(not &1["archived"] or to_string(&1["id"]) in chosen))
    |> Enum.map(&{&1["label"], to_string(&1["id"])})
  end
end
