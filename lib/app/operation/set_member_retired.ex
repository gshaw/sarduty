defmodule App.Operation.SetMemberRetired do
  @moduledoc """
  A team admin marks a member as retired, or as rejoined, from their Standing tab, on
  every team (#1053). It is D4H's retire and unretire: the member stays, with the day
  they retired as their leave date, and stops counting as a manager. Members are never
  deleted.

  D4H refuses to retire a member who holds any of the team's items, whatever the item's
  status, and its refusal doesn't say why (tested 2026-11-12). So this refuses first, on
  D4H and Records teams alike, and says so.
  """

  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Model.ChangeSetRow
  alias App.Model.EquipmentItem
  alias App.Model.Member
  alias App.Model.Team
  alias App.Operation.ApplyEdit
  alias App.Operation.SaveMember
  alias App.Repo

  @doc "`{:ok, member}` or `{:error, text}`."
  def call(%Team{} = team, %Member{team_id: team_id} = member, retired?, %User{} = user, now)
      when team_id == team.id do
    left_at =
      now |> Service.Period.today(team.timezone) |> Service.Convert.day_start(team.timezone)

    with :ok <- check(team, member, retired?, now),
         {:ok, _d4h_member_id} <-
           ApplyEdit.call(team, user, plan(member, retired?, left_at), now) do
      {:ok, save_copy(member, retired?, left_at)}
    end
  end

  # What D4H now has, so the tab shows it at once; the next sync confirms it.
  defp save_copy(member, true = _retired?, left_at),
    do: member |> Ecto.Changeset.change(d4h_status: "RETIRED", left_at: left_at) |> Repo.update!()

  defp save_copy(member, false = _retired?, _left_at),
    do: member |> Ecto.Changeset.change(d4h_status: "OPERATIONAL", left_at: nil) |> Repo.update!()

  defp check(team, member, true = _retired?, now) do
    held = team |> EquipmentItem.held_by(member) |> length()

    cond do
      SaveMember.last_admin?(team, member, now) ->
        {:error, "Make another member a team admin first."}

      held > 0 ->
        {:error, held_text(member, held, D4H.service_name(team))}

      true ->
        :ok
    end
  end

  defp check(_team, _member, false = _retired?, _now), do: :ok

  # "Sam Rivera still holds 1 item. Get it back and move it in D4H first." The API
  # can't move an item, so the team admin does it in D4H's web app.
  defp held_text(member, held, service) do
    items = Service.Format.count(held, one: "%d item", many: "%d items")
    "#{member.name} still holds #{items}. Get it back and move it in #{service} first."
  end

  def plan(%Member{} = member, true = _retired?, left_at) do
    %ChangeSetRow{
      action: :retire_member,
      member_id: member.id,
      d4h_record_id: member.d4h_member_id,
      old_value: %{"status" => member.d4h_status},
      new_value: %{"status" => "RETIRED", "left_at" => DateTime.to_iso8601(left_at)}
    }
  end

  def plan(%Member{} = member, false = _retired?, _now) do
    %ChangeSetRow{
      action: :rejoin_member,
      member_id: member.id,
      d4h_record_id: member.d4h_member_id,
      old_value: %{"status" => member.d4h_status},
      new_value: %{"status" => "OPERATIONAL"}
    }
  end
end
