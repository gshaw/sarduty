defmodule App.ViewModel.MilestoneFilterViewModel do
  @moduledoc """
  The team's Milestones page filters (#389): a member, a kind, and a period. The period
  opens on the last 90 days, for thanking people at a meeting or in a newsletter; a
  member's sidebar link asks for All.
  """

  use App, :view_model

  @primary_key false
  embedded_schema do
    field :member, :integer
    field :kind, :string
    field :when, :string, default: "90d"
    field :page, :integer
  end

  @default_when "90d"
  @page_size 50

  def default_when, do: @default_when

  def kinds,
    do: [
      {"Milestones", ""},
      {"Hours", "hours"},
      {"Years", "years"},
      {"Incidents", "incidents"}
    ]

  @doc "All, the rolling periods, then each year with a milestone, newest first."
  def when_kinds(milestones) do
    years =
      milestones
      |> Enum.map(&Integer.to_string(&1.on.year))
      |> Enum.uniq()

    [{"All", "all"}] ++ Service.Period.rolling_kinds() ++ Enum.map(years, &{&1, &1})
  end

  @doc "The members with a milestone, by name, for the member filter."
  def member_kinds(milestones) do
    milestones
    |> Enum.map(& &1.member)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.name)
    |> Enum.map(&{&1.name, Integer.to_string(&1.id)})
  end

  def validate(params) do
    changeset =
      %__MODULE__{}
      |> cast(params, [:member, :kind, :when, :page])
      |> validate_inclusion(:kind, ~w(hours years incidents))
      |> validate_change(:when, fn :when, value ->
        if Service.Period.valid?(value), do: [], else: [when: "is not a period"]
      end)

    case apply_action(changeset, :replace) do
      {:ok, filter_options} -> {:ok, filter_options, changeset}
      {:error, _} = result -> result
    end
  end

  @doc """
  The milestones the filters pick, in the order given. A rolling period counts back
  from today in the team's zone; a year is the calendar year.
  """
  def filter(milestones, filter_options, timezone, now) do
    in_period? = period_filter(filter_options.when, timezone, now)

    Enum.filter(milestones, fn milestone ->
      (is_nil(filter_options.member) or milestone.member.id == filter_options.member) and
        (is_nil(filter_options.kind) or Atom.to_string(milestone.kind) == filter_options.kind) and
        in_period?.(milestone.on)
    end)
  end

  defp period_filter("all", _timezone, _now), do: fn _on -> true end

  defp period_filter(period, timezone, now) do
    {starts, finishes} = Service.Period.bounds(period, timezone, now)
    first = local_date(starts, timezone)
    today = local_date(now, timezone)

    last =
      if String.ends_with?(period, "d"),
        do: today,
        else: finishes |> local_date(timezone) |> Date.add(-1)

    &(Date.compare(&1, first) != :lt and Date.compare(&1, last) != :gt)
  end

  defp local_date(datetime, timezone),
    do: datetime |> DateTime.shift_zone!(timezone) |> DateTime.to_date()

  @doc "One page of 50, as `App.Page`."
  def page(milestones, page_number) do
    total = length(milestones)
    page_number = max(page_number || 1, 1)

    %App.Page{
      entries: milestones |> Enum.drop((page_number - 1) * @page_size) |> Enum.take(@page_size),
      page_number: page_number,
      page_size: @page_size,
      total_entries: total,
      total_pages: max(1, ceil(total / @page_size))
    }
  end
end
