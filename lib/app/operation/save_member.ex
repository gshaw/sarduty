defmodule App.Operation.SaveMember do
  @moduledoc """
  A team admin adds a member to a team on SAR Duty Records, or changes their details
  (docs/records.md). plan/3 turns the form into a change set row; call/5 applies it
  through App.Operation.ApplyEdit and returns the member as the sync copied it.
  """

  alias App.Accounts.User
  alias App.Model.ChangeSetRow
  alias App.Model.Member
  alias App.Model.Team
  alias App.Operation.ApplyEdit
  alias App.ViewModel.MemberFormViewModel

  @owner 0
  @member 2

  @doc """
  `{:ok, member}`, `{:error, changeset}` for the form, or `{:error, text}` when the
  store refused the change.
  """
  def call(%Team{} = team, member, params, %User{} = user, now) do
    form = MemberFormViewModel.from_member(member, team.timezone, nil)

    with {:ok, values} <- MemberFormViewModel.validate(form, params) do
      member |> plan(values, team.timezone) |> save(team, member, user, now)
    end
  end

  defp save(:unchanged, _team, member, _user, _now), do: {:ok, member}

  defp save(%{new_value: %{"permission" => @member}} = row, team, member, user, now) do
    if last_admin?(team, member, now),
      do: {:error, "Make another member a team admin first."},
      else: apply_row(team, user, row, now)
  end

  defp save(row, team, _member, user, now), do: apply_row(team, user, row, now)

  @doc "Whether `member` is the team's only team admin, so taking it away locks the team out."
  def last_admin?(_team, nil, _now), do: false

  def last_admin?(team, member, now) do
    team |> Member.get_managers(now) |> Enum.map(& &1.id) == [member.id]
  end

  defp apply_row(team, user, row, now) do
    with {:ok, d4h_member_id} <- ApplyEdit.call(team, user, row, now) do
      {:ok, Member.get_by(team_id: team.id, d4h_member_id: d4h_member_id)}
    end
  end

  @doc """
  The change set row for the form's values, or `:unchanged`. An update names only the
  fields that differ, with their old values beside them.
  """
  def plan(nil, %MemberFormViewModel{} = values, timezone),
    do: %ChangeSetRow{action: :create_member, old_value: %{}, new_value: fields(values, timezone)}

  def plan(%Member{} = member, %MemberFormViewModel{} = values, timezone) do
    old = current(member, timezone)

    new =
      values
      |> fields(timezone)
      |> Map.reject(fn {key, value} -> old[key] == value end)
      |> keep_retired(member)

    if new == %{} do
      :unchanged
    else
      %ChangeSetRow{
        action: :update_member,
        member_id: member.id,
        d4h_record_id: member.d4h_member_id,
        old_value: Map.take(old, Map.keys(new)),
        new_value: new
      }
    end
  end

  # A retired member's status stays RETIRED: "Mark as rejoined" brings them back, with
  # their left date cleared.
  defp keep_retired(new, %Member{d4h_status: "RETIRED"}), do: Map.delete(new, "status")
  defp keep_retired(new, _member), do: new

  defp fields(values, timezone) do
    %{
      "name" => values.name,
      "ref_id" => blank_to_nil(values.ref_id),
      "position" => blank_to_nil(values.position),
      "email" => values.email |> blank_to_nil() |> downcase(),
      "phone" => blank_to_nil(values.phone),
      "address" => blank_to_nil(values.address),
      "status" => values.status,
      "permission" => if(values.team_admin, do: @owner, else: @member),
      "joined_at" =>
        values.joined_on
        |> Service.Convert.local_to_utc(~T[00:00:00], timezone)
        |> DateTime.to_iso8601()
    }
  end

  # What the copy holds, in the same shape. A retired member reads as operational, as
  # the form shows them, so saving their details leaves them retired. Any manager's
  # access reads as a team admin's, and the joining day as midnight, as the form sends.
  defp current(member, timezone) do
    %{
      "name" => member.name,
      "ref_id" => blank_to_nil(member.ref_id),
      "position" => blank_to_nil(member.position),
      "email" => blank_to_nil(member.email),
      "phone" => blank_to_nil(member.phone),
      "address" => blank_to_nil(member.address),
      "status" => if(member.d4h_status == "RETIRED", do: "OPERATIONAL", else: member.d4h_status),
      "permission" => if(member.d4h_permission in [0, 1], do: @owner, else: @member),
      "joined_at" => member.joined_at && midnight(member.joined_at, timezone)
    }
  end

  defp midnight(datetime, timezone) do
    {date, _time} = Service.Convert.utc_to_local(datetime, timezone)
    date |> Service.Convert.local_to_utc(~T[00:00:00], timezone) |> DateTime.to_iso8601()
  end

  defp downcase(nil), do: nil
  defp downcase(email), do: String.downcase(email)

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
