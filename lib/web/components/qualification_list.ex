defmodule Web.Components.QualificationList do
  @moduledoc """
  A member's qualifications grouped by when they expire (#308), from
  `App.ViewData.MemberRecords.group_awards/2`. The same list on a member's own pages and a
  team admin's member page; it takes rows and a time zone, not a team, so an org page can
  use it too. See /styles/qualification-list.
  """

  use Web, :function_component

  import Web.Components.A

  attr :id, :string, required: true
  attr :groups, :list, required: true, doc: "`MemberRecords.group_awards/2`"
  attr :timezone, :string, required: true

  attr :href, :any,
    default: nil,
    doc: "a function from a qualification to its page, or nil for no links"

  attr :earlier, :boolean,
    default: false,
    doc: "list the awards a renewal replaced, for team admins; members see the first year"

  slot :action, doc: "after each award, such as Remove; takes the award with `:let`"

  def qualification_list(assigns) do
    ~H"""
    <div id={@id}>
      <section
        :for={{group, rows} <- @groups}
        id={"#{@id}-#{group_id(group)}"}
        class="mb-6 last:mb-0"
      >
        <h3 class={["subheading", group == :expired && "text-text-muted"]}>
          {group_title(group)}
        </h3>
        <ul class="divide-y divide-border-subtle">
          <li
            :for={row <- rows}
            id={"#{@id}-#{row.award.qualification_id}"}
            class="py-2"
          >
            <div class="flex items-start gap-3">
              <div class="flex-1 min-w-0">
                <span class="block">
                  <.a :if={@href} navigate={@href.(row.award.qualification)}>
                    {row.award.qualification.title}
                  </.a>
                  <span :if={!@href}>{row.award.qualification.title}</span>
                </span>
                <span class="hint block">{summary(group, row, @earlier, @timezone)}</span>
              </div>
              {render_slot(@action, row.award)}
            </div>
            <ul :if={@earlier && row.earlier != []} class="mt-1">
              <li
                :for={award <- row.earlier}
                id={"#{@id}-award-#{award.id}"}
                class="flex items-start gap-3"
              >
                <span class="hint flex-1">{held(award, @timezone)}</span>
                {render_slot(@action, award)}
              </li>
            </ul>
          </li>
        </ul>
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

  # An expired one reads as something they held. A renewed one, for a member, says when
  # they first held it; team admins see each earlier award instead.
  defp summary(:expired, row, _earlier, timezone),
    do: "Held " <> span(row.first_started_at, row.award.ends_at, timezone)

  defp summary(_group, row, earlier, timezone) do
    [
      expiry(row.award, timezone),
      !earlier && row.earlier != [] && row.first_started_at &&
        "First held #{Service.YearRange.year_in(row.first_started_at, timezone)}"
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  defp expiry(%{ends_at: nil}, _timezone), do: "Does not expire"

  defp expiry(%{ends_at: ends_at}, timezone),
    do: "Expires #{Service.Format.date_long(ends_at, timezone)}"

  defp held(award, timezone) do
    {first, rest} = award.starts_at |> span(award.ends_at, timezone) |> String.split_at(1)
    String.upcase(first) <> rest
  end

  defp span(nil, nil, _timezone), do: "no dates"
  defp span(nil, ends_at, timezone), do: "until #{Service.Format.month_year(ends_at, timezone)}"

  defp span(starts_at, nil, timezone),
    do: "from #{Service.Format.month_year(starts_at, timezone)}"

  defp span(starts_at, ends_at, timezone),
    do:
      "#{Service.Format.month_year(starts_at, timezone)} – #{Service.Format.month_year(ends_at, timezone)}"
end
