defmodule Web.QualificationText do
  @moduledoc """
  The words for a member's qualifications (#308), so the member's page, a team admin's
  member tab, and later org pages say the same thing. The rows are
  `App.ViewData.MemberRecords.qualification_rows/2`.
  """

  alias App.Model.MemberQualificationAward
  alias App.Operation.BuildGroupRulePreview
  alias Service.Format

  @doc "Greys an expired row."
  def row_class(%{status: :expired}), do: "is-muted"
  def row_class(_row), do: nil

  @doc ~s(The reminder's title: "First Aid expires Dec 5, 2026" or "2 qualifications expire within #{BuildGroupRulePreview.expiring_days()} days".)
  def expiring_title([row], timezone),
    do:
      "#{row.award.qualification.title} expires #{Format.date_short(row.award.ends_at, timezone)}"

  def expiring_title(rows, _timezone),
    do:
      "#{length(rows)} qualifications expire within #{BuildGroupRulePreview.expiring_days()} days"

  @doc "The reminder's body: what to renew, and by when."
  def expiring_body([_row], _timezone), do: "Renew it before then."

  def expiring_body(rows, timezone) do
    names =
      Enum.map(rows, fn row ->
        "#{row.award.qualification.title} on #{Format.date_short(row.award.ends_at, timezone)}"
      end)

    "#{Enum.join(names, ", ")}. Renew them before then."
  end

  @doc ~s(When it ends: "Nov 30, 2026", "Does not expire", or "Expired Sep 30, 2024".)
  def expires(%{ends_at: nil}, _now, _timezone), do: "Does not expire"

  def expires(%{ends_at: ends_at} = award, now, timezone) do
    if MemberQualificationAward.expired?(award, now),
      do: "Expired #{Format.date_short(ends_at, timezone)}",
      else: Format.date_short(ends_at, timezone)
  end

  @doc "The year the member first held it, or nil when D4H has no start."
  def first_held(%{first_started_at: nil}, _timezone), do: nil

  def first_held(%{first_started_at: started}, timezone),
    do: Service.YearRange.year_in(started, timezone)

  @doc ~s(An earlier award's dates: "Jun 2019 – Jun 2022".)
  def held(%{starts_at: nil, ends_at: nil}, _timezone), do: "No dates"

  def held(%{starts_at: nil, ends_at: ends_at}, timezone),
    do: "Until #{Format.month_year(ends_at, timezone)}"

  def held(%{starts_at: starts_at, ends_at: nil}, timezone),
    do: "From #{Format.month_year(starts_at, timezone)}"

  def held(%{starts_at: starts_at, ends_at: ends_at}, timezone),
    do: "#{Format.month_year(starts_at, timezone)} – #{Format.month_year(ends_at, timezone)}"
end
