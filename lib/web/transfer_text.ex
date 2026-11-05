defmodule Web.TransferText do
  @moduledoc """
  The words for a transfer (#892), so the sending team's pages, its email, and the
  receiving team's page say the same thing.
  """

  alias App.Model.MemberQualificationAward
  alias App.Model.Transfer
  alias App.Model.TransferAward
  alias Service.Format

  @doc ~s(An award's dates: "Jul 30, 2026 to Jul 30, 2029", "From Nov 4, 2020", or "No dates".)
  def dates(%{starts_at: nil, ends_at: nil}, _timezone), do: "No dates"

  def dates(%{starts_at: nil, ends_at: ends_at}, timezone),
    do: "Until #{Format.date_short(ends_at, timezone)}"

  def dates(%{starts_at: starts_at, ends_at: nil}, timezone),
    do: "From #{Format.date_short(starts_at, timezone)}"

  def dates(%{starts_at: starts_at, ends_at: ends_at}, timezone),
    do: "#{Format.date_short(starts_at, timezone)} to #{Format.date_short(ends_at, timezone)}"

  @doc """
  One line of What will be transferred: "First aid, Jul 30, 2026 to Jul 30, 2029, with
  its certificate". An award that ended by `now` says so.
  """
  def award(%TransferAward{} = award, now, timezone) do
    dates = lowercase_first(dates(award, timezone))
    expired = if MemberQualificationAward.expired?(award, now), do: ", expired"
    certificate = if TransferAward.certificate?(award), do: ", with its certificate"
    "#{award.qualification_title}, #{dates}#{expired}#{certificate}"
  end

  # "From Nov 4" reads "from Nov 4" mid-sentence; a date stays as it is.
  defp lowercase_first("From " <> rest), do: "from " <> rest
  defp lowercase_first("Until " <> rest), do: "until " <> rest
  defp lowercase_first("No dates"), do: "no dates"
  defp lowercase_first(dates), do: dates

  @doc """
  Who made the code and where it stands: "Made by Alex Chen. Works once, until Dec 3,
  2026. Not used yet." `made_by` and `cancelled_by` are names, or nil.
  """
  def status_line(%Transfer{} = transfer, made_by, cancelled_by, now, timezone) do
    made = if made_by, do: "Made by #{made_by}. "

    status =
      case Transfer.status(transfer, now) do
        :open ->
          "Works once, until #{Format.date_short(transfer.expires_at, timezone)}. Not used yet."

        :used ->
          "Used by #{transfer.used_by_team.name} on #{Format.date_short(transfer.used_at, timezone)}."

        :cancelled ->
          by = if cancelled_by, do: " by #{cancelled_by}"
          "Cancelled#{by} on #{Format.date_short(transfer.cancelled_at, timezone)}."

        :expired ->
          "Expired on #{Format.date_short(transfer.expires_at, timezone)}."
      end

    "#{made}#{status}"
  end
end
