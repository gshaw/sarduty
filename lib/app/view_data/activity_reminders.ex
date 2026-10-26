defmodule App.ViewData.ActivityReminders do
  @moduledoc """
  What an activity's Members table shows about reminders (#444): each member's latest,
  and the last batch with how many of its members replied since. `rows` are the
  activity's invited rows, with their members.
  """

  @doc "Each member's latest reminder, by member id."
  def latest(reminders) do
    reminders
    |> Enum.sort_by(& &1.sent_at, DateTime)
    |> Map.new(&{&1.member_id, &1})
  end

  @doc """
  The last send, as `%{sent_at:, sent_by_user:, sent:, sending:, failed:,
  replied_since:}`, or nil
  before the first. Replied since counts its members who have a reply now: they had
  none when it went.
  """
  def last_batch([], _rows), do: nil

  def last_batch(reminders, rows) do
    sent_at = reminders |> Enum.map(& &1.sent_at) |> Enum.max(DateTime)
    batch = Enum.filter(reminders, &(DateTime.compare(&1.sent_at, sent_at) == :eq))
    by_status = Enum.frequencies_by(batch, & &1.status)

    %{
      sent_at: sent_at,
      sent_by_user: hd(batch).sent_by_user,
      sent: Map.get(by_status, :sent, 0),
      sending: Map.get(by_status, :queued, 0),
      failed: Map.get(by_status, :failed, 0),
      replied_since: replied_since(batch, rows)
    }
  end

  defp replied_since(batch, rows) do
    replied = for row <- rows, row.status != "requested", into: MapSet.new(), do: row.member_id
    Enum.count(batch, &MapSet.member?(replied, &1.member_id))
  end
end
