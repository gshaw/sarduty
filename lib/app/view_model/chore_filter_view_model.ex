defmodule App.ViewModel.ChoreFilterViewModel do
  @moduledoc """
  The Chores page filters for team admins (#1116): a chore category and a member, by
  local id, on Waiting, Accepted, and Declined, and a period on Accepted and Declined.
  The period opens on the last 12 months, in whole months, so a month's chore activity
  shows whole or not at all. Waiting has no period: an old chore waiting never hides.
  """

  use App, :view_model

  @primary_key false
  embedded_schema do
    field :category, :integer
    field :member, :integer
    field :when, :string, default: "12mo"
  end

  @default_when "12mo"
  @default_months 12

  def default_when, do: @default_when

  def validate(params) do
    changeset =
      %__MODULE__{}
      |> cast(params, [:category, :member, :when])
      |> validate_change(:when, fn :when, value ->
        if valid_when?(value), do: [], else: [when: "is not a period"]
      end)

    case apply_action(changeset, :replace) do
      {:ok, filter_options} -> {:ok, filter_options, changeset}
      {:error, _} = result -> result
    end
  end

  defp valid_when?(value),
    do: value == "all" or value =~ ~r/\A\d{4}\z/ or Service.Period.month_period?(value)

  @doc "The month periods, each year with chores, newest first, then All."
  def when_kinds(years),
    do:
      Enum.concat([
        Service.Period.month_kinds(),
        Enum.map(years, &{"#{&1}", "#{&1}"}),
        [{"All", "all"}]
      ])

  @doc """
  The first and last dates the period covers, in the team's zone, or nil for All. A year
  is the calendar year.
  """
  def dates("all", _now, _timezone), do: nil

  def dates(period, now, timezone) do
    case Integer.parse(period) do
      {months, "mo"} -> Service.Period.month_dates(months, now, timezone)
      {year, ""} -> {Date.new!(year, 1, 1), Date.new!(year, 12, 31)}
    end
  end

  @doc """
  The `when` that shows a chore done on `date`: its year when the default period, the last
  12 months, leaves it out, else nil for the default.
  """
  def when_for(%Date{} = date, now, timezone) do
    {first, _last} = Service.Period.month_dates(@default_months, now, timezone)
    if Date.before?(date, first), do: Integer.to_string(date.year)
  end

  @doc """
  The query params for `view`: Category and Member on any team view, and a period other
  than the default only on Accepted and Declined. Yours takes none.
  """
  def query_params(:yours, _filter_options), do: [view: :yours]

  def query_params(view, filter_options) do
    when_value =
      if view != :waiting and filter_options.when != @default_when, do: filter_options.when

    [
      view: if(view != :waiting, do: view),
      category: filter_options.category,
      member: filter_options.member,
      when: when_value
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end
end
