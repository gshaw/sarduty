defmodule App.Operation.SetMemberLeft do
  @moduledoc """
  A team admin marks a hosted team's member as left, or as rejoined
  (docs/hosted-d4h.md). Leaving is D4H's retire: the member stays, with the day they
  left, and stops counting as a manager. Members are never deleted.
  """

  alias App.Accounts.User
  alias App.Model.ChangeSetRow
  alias App.Model.Member
  alias App.Model.Team
  alias App.Operation.ApplyEdit

  @doc "`{:ok, member}` or `{:error, text}`."
  def call(%Team{} = team, %Member{team_id: team_id} = member, left?, %User{} = user, now)
      when team_id == team.id do
    row = plan(member, left?, now)

    with {:ok, _d4h_member_id} <- ApplyEdit.call(team, user, row, now) do
      {:ok, Member.find!(team, member.id)}
    end
  end

  def plan(%Member{} = member, true = _left?, now) do
    %ChangeSetRow{
      action: :retire_member,
      member_id: member.id,
      d4h_record_id: member.d4h_member_id,
      old_value: %{"status" => member.d4h_status},
      new_value: %{
        "status" => "RETIRED",
        "left_at" => now |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      }
    }
  end

  def plan(%Member{} = member, false = _left?, _now) do
    %ChangeSetRow{
      action: :rejoin_member,
      member_id: member.id,
      d4h_record_id: member.d4h_member_id,
      old_value: %{"status" => member.d4h_status},
      new_value: %{"status" => "OPERATIONAL"}
    }
  end
end
