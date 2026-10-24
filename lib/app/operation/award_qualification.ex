defmodule App.Operation.AwardQualification do
  @moduledoc """
  A team admin awards a qualification to a member of a team on SAR Duty Records, or
  removes an award (docs/records.md). Each is one change set row applied through
  App.Operation.ApplyEdit, so it shows in the member's history. An award can take a
  certificate (#493): a second row, once the award is in, uploads it.
  """

  alias App.Accounts.User
  alias App.Model.ChangeSetRow
  alias App.Model.Member
  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
  alias App.Model.Team
  alias App.Operation.ApplyEdit
  alias App.Repo
  alias App.ViewModel.AwardFormViewModel

  @doc """
  `:ok`, `{:error, changeset}` for the form, or `{:error, text}`. `certificate` is a file
  from `Service.CertificateFile.prepare/2`, or nil. `{:award_only, text}` when the award
  went in but its certificate did not upload.
  """
  def award(
        %Team{} = team,
        %Member{team_id: team_id} = member,
        params,
        %User{} = user,
        now,
        certificate \\ nil
      )
      when team_id == team.id do
    with {:ok, values} <- AwardFormViewModel.validate(%AwardFormViewModel{}, params),
         {:ok, qualification} <- find_qualification(team, values.qualification_id),
         row = plan(member, qualification, values, team.timezone),
         {:ok, award_id} <- ApplyEdit.call(team, user, row, now) do
      attach(team, user, now, {member, qualification, award_id}, certificate)
    end
  end

  defp attach(_team, _user, _now, _award, nil), do: :ok

  defp attach(team, user, now, {member, qualification, award_id}, file) do
    row = %ChangeSetRow{
      action: :attach_award_document,
      member_id: member.id,
      old_value: %{},
      new_value: %{"title" => qualification.title, "d4h_award_id" => award_id}
    }

    document = %{bytes: file.bytes, filename: file.file_name, content_type: file.content_type}

    case ApplyEdit.call(team, user, row, now, document: document) do
      {:ok, _document_id} ->
        :ok

      {:error, text} ->
        {:award_only,
         "#{qualification.title} is awarded, but its certificate did not upload. #{text}"}
    end
  end

  @doc "`:ok` or `{:error, text}`."
  def remove(%Team{} = team, %MemberQualificationAward{} = award, %User{} = user, now) do
    award = Repo.preload(award, [:member, :qualification])
    true = award.member.team_id == team.id

    row = %ChangeSetRow{
      action: :remove_award,
      member_id: award.member_id,
      d4h_record_id: award.d4h_award_id,
      old_value: %{"title" => award.qualification.title},
      new_value: %{}
    }

    with {:ok, _id} <- ApplyEdit.call(team, user, row, now), do: :ok
  end

  def plan(member, qualification, values, timezone) do
    %ChangeSetRow{
      action: :award_qualification,
      member_id: member.id,
      old_value: %{},
      new_value: %{
        "title" => qualification.title,
        "d4h_qualification_id" => qualification.d4h_qualification_id,
        "d4h_member_id" => member.d4h_member_id,
        "starts_at" => midnight(values.starts_on, timezone),
        "ends_at" => values.ends_on && midnight(values.ends_on, timezone)
      }
    }
  end

  defp find_qualification(team, id) do
    case Repo.get_by(Qualification, id: id, team_id: team.id) do
      nil -> {:error, "Select a qualification."}
      qualification -> {:ok, qualification}
    end
  end

  defp midnight(date, timezone),
    do: date |> Service.Convert.local_to_utc(~T[00:00:00], timezone) |> DateTime.to_iso8601()
end
