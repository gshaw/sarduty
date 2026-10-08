defmodule Web.Components.ChangeHistory do
  use Web, :function_component

  import Web.Components.Table

  alias App.ViewData.ChangeHistory

  @doc """
  A member's or an activity's history, from `App.ViewData.ChangeHistory`: SAR Duty's
  own changes to D4H, and changes the refresh saw in D4H.
  """
  attr :id, :string, required: true
  attr :entries, :list, required: true
  attr :timezone, :string, required: true

  def change_history(assigns) do
    ~H"""
    <.table
      :if={@entries != []}
      id={@id}
      rows={@entries}
      row_id={&"#{@id}-#{&1.id}"}
      class="table-striped table-stack"
    >
      <:col :let={entry} label="When" class="w-px whitespace-nowrap">
        {when_text(entry, @timezone)}
      </:col>
      <:col :let={entry} label="Change">
        {entry.text}
        <div :if={entry[:reason]} class="text-text-muted">{entry.reason}</div>
      </:col>
      <:col :let={entry} label="By">
        {by_text(entry)}
      </:col>
    </.table>
    <p :if={@entries == []} id={"#{@id}-empty"}>
      No changes yet. SAR Duty started keeping history in October 2026.
    </p>
    """
  end

  # D4H doesn't say when a change was made, only that a refresh saw it.
  defp when_text(%{by: :d4h, seen_after: %DateTime{} = after_at, at: at}, tz) do
    if same_day?(after_at, at, tz),
      do:
        "#{Service.Format.month_day_time(after_at, tz)} to #{Service.Format.time_short(at, tz)}",
      else:
        "#{Service.Format.month_day_time(after_at, tz)} to #{Service.Format.month_day_time(at, tz)}"
  end

  defp when_text(%{at: at}, tz), do: Service.Format.month_day_time(at, tz)

  defp same_day?(a, b, tz), do: local_date(a, tz) == local_date(b, tz)

  defp local_date(datetime, tz), do: datetime |> DateTime.shift_zone!(tz) |> DateTime.to_date()

  defp by_text(%{by: :d4h}), do: "Someone in D4H"

  defp by_text(%{by: :sar_duty, source: source, applied_by: applied_by}) do
    from = "SAR Duty (#{ChangeHistory.source_label(source)})"
    if applied_by, do: "#{from}, sent by #{applied_by}", else: from
  end
end
