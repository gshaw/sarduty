defmodule Web.Components.QualificationList do
  @moduledoc """
  A member's qualifications grouped by when they expire (#308), from
  `App.ViewData.MemberRecords.group_awards/2`: a heading and a table for each group, one
  row per qualification. The same tables on a member's own pages and a team admin's member
  page; it takes rows and a time zone, not a team, so an org page can use it too. See
  /styles/qualification-list.
  """

  use Web, :function_component

  import Web.Components.A
  import Web.Components.Table

  attr :id, :string, required: true
  attr :groups, :list, required: true, doc: "`MemberRecords.group_awards/2`"
  attr :timezone, :string, required: true

  attr :href, :any,
    default: nil,
    doc: "a function from a qualification to its page, or nil for no links"

  attr :earlier, :boolean,
    default: false,
    doc: "a column of the awards a renewal replaced, for team admins"

  slot :action, doc: "after each award, such as Remove; takes the award with `:let`"

  def qualification_list(assigns) do
    ~H"""
    <div id={@id}>
      <section :for={{group, rows} <- @groups} class="mb-6 last:mb-0">
        <h3 class={["subheading", group == :expired && "text-text-muted"]}>
          {group_title(group)}
        </h3>
        <.table
          id={"#{@id}-#{group_id(group)}"}
          rows={rows}
          row_id={&"#{@id}-#{&1.award.qualification_id}"}
          class="table-striped"
        >
          <:col :let={row} label="Qualification">
            <.a :if={@href} navigate={@href.(row.award.qualification)}>
              {row.award.qualification.title}
            </.a>
            <span :if={!@href}>{row.award.qualification.title}</span>
          </:col>
          <:col :let={row} :if={group != :expired} label="Expires" class="w-px whitespace-nowrap">
            {expiry(row.award, @timezone)}
          </:col>
          <:col :let={row} :if={group == :expired} label="Held" class="w-px whitespace-nowrap">
            {span(row.first_started_at, row.award.ends_at, @timezone)}
          </:col>
          <:col :let={row} :if={group != :expired} label="First held" class="w-px whitespace-nowrap">
            {row.first_started_at && Service.YearRange.year_in(row.first_started_at, @timezone)}
          </:col>
          <:col :let={row} :if={@earlier} label="Earlier awards" class="w-px whitespace-nowrap">
            <span
              :for={award <- row.earlier}
              id={"#{@id}-award-#{award.id}"}
              class="flex items-center gap-2"
            >
              {span(award.starts_at, award.ends_at, @timezone)}
              {render_slot(@action, award)}
            </span>
          </:col>
          <:col :let={row} :if={@action != []} class="w-px whitespace-nowrap">
            {render_slot(@action, row.award)}
          </:col>
        </.table>
      </section>
    </div>
    """
  end

  defp group_id(group), do: group |> Atom.to_string() |> String.replace("_", "-")

  defp group_title(:within_60_days), do: "Expiring within 60 days"
  defp group_title(:within_180_days), do: "Expiring within 180 days"
  defp group_title(:later), do: "Expiring later"
  defp group_title(:never), do: "Does not expire"
  defp group_title(:expired), do: "Expired"

  defp expiry(%{ends_at: nil}, _timezone), do: "Does not expire"
  defp expiry(%{ends_at: ends_at}, timezone), do: Service.Format.date_short(ends_at, timezone)

  # "Mar 2019 – Sep 2024": what a member held, for an expired one or an earlier award.
  defp span(nil, nil, _timezone), do: "No dates"
  defp span(nil, ends_at, timezone), do: "Until #{Service.Format.month_year(ends_at, timezone)}"

  defp span(starts_at, nil, timezone),
    do: "From #{Service.Format.month_year(starts_at, timezone)}"

  defp span(starts_at, ends_at, timezone),
    do:
      "#{Service.Format.month_year(starts_at, timezone)} – #{Service.Format.month_year(ends_at, timezone)}"
end
