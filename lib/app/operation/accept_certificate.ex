defmodule App.Operation.AcceptCertificate do
  @moduledoc """
  A team admin accepts a member's certificate (#493): one change set, applied at once,
  gives the award in D4H and uploads the file to it. Then the award goes into the copy
  with its certificate, so pages and group rules see it before the next refresh, and
  SAR Duty's copy of the file is deleted.

  D4H's API can't remove an award, so it is never sent twice. When D4H already has the
  member's award of the qualification from the same day, the set only attaches the file
  to it, or refuses when that award has a certificate (App.Operation.FindCertificateAward).
  When the upload fails, the award stays, the certificate keeps waiting with its file, and
  accepting again applies the same set: only the failed row goes. Until the award is in
  D4H, the team admin's qualification and dates replace the member's, and each accept is
  a new set.
  """

  import Ecto.Query

  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Model.Certificate
  alias App.Model.CertificateFile
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.Member
  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
  alias App.Model.Team
  alias App.Operation.ApplyChangeSet
  alias App.Operation.AwardQualification
  alias App.Operation.FindCertificateAward
  alias App.Operation.SaveCertificate
  alias App.Repo

  @doc """
  `{:ok, certificate}` once it is in D4H. Otherwise `{:error, changeset}` for the form,
  `{:error, :decided}`, or `{:error, text}` saying what did not go through.
  """
  def call(%Team{} = team, %Certificate{team_id: team_id} = certificate, params, user, now)
      when team_id == team.id and is_struct(user, User) do
    # One change at a time per certificate, so two team admins never award it twice, and
    # a member's change or another team admin's decline waits until it is in D4H.
    SaveCertificate.locked(certificate, fn ->
      current = Repo.get_by!(Certificate, id: certificate.id, team_id: team.id)

      with :ok <- check_waiting(current),
           {:ok, current} <- save_values(current, params),
           {:ok, bytes} <- file(current) do
        send_set(team, current, bytes, user, now)
      end
    end)
  end

  defp send_set(team, current, bytes, user, now) do
    current = Repo.preload(current, [:member, :qualification, change_set: :rows])

    with {:ok, set} <- change_set(team, current, user),
         {:ok, _rows} <- apply_set(team, set, user, now, current, bytes) do
      rows = set |> Repo.preload(:rows, force: true) |> Map.fetch!(:rows)
      finish(rows, current, user, now)
    end
  end

  defp check_waiting(%Certificate{status: :waiting}), do: :ok
  defp check_waiting(_certificate), do: {:error, :decided}

  # Once the award is in D4H its dates are D4H's, so the form's are not read.
  defp save_values(current, params) do
    if Certificate.dates_locked?(current) do
      {:ok, current}
    else
      current
      |> Certificate.accept_changeset(params, SaveCertificate.qualification_ids(current.team_id))
      |> Repo.update()
    end
  end

  defp file(current) do
    case CertificateFile.bytes(current) do
      nil -> {:error, "The file is gone. Ask the member to send the certificate again."}
      bytes -> {:ok, bytes}
    end
  end

  # The same set while its award is in D4H, so only the upload goes again. Otherwise a
  # new one, from the qualification and dates as they are now, and D4H's awards now.
  defp change_set(team, current, user) do
    case {current.change_set, current.d4h_award_id} do
      {%ChangeSet{} = set, award_id} when is_integer(award_id) ->
        {:ok, set}

      {old, _award_id} ->
        with {:ok, rows} <- rows(team, current), do: propose(team, current, old, rows, user)
    end
  end

  defp propose(team, current, old, rows, user) do
    if old, do: ChangeSet.discard!(old, DateTime.utc_now())

    set =
      ChangeSet.propose!(
        %ChangeSet{team_id: team.id, source: :certificates, proposed_by_user_id: user.id},
        rows
      )

    current |> Ecto.Changeset.change(change_set_id: set.id) |> Repo.update!()
    {:ok, set}
  end

  defp rows(team, current) do
    %{member: member, qualification: qualification} = current

    case FindCertificateAward.call(team, current) do
      {:ok, nil} ->
        {:ok, plan(member, qualification, current, team.timezone)}

      {:ok, %{certificate?: false} = award} ->
        {:ok, [attach(member, qualification, award)]}

      {:ok, %{certificate?: true}} ->
        {:error, "This member has this award already, with a certificate. Decline this one."}

      {:error, text} ->
        {:error, text}
    end
  end

  @doc """
  The set's rows: the award, from `values`' `starts_on` and `ends_on`, then the file on
  the award the first row makes.
  """
  def plan(%Member{} = member, %Qualification{} = qualification, values, timezone) do
    [
      AwardQualification.plan(member, qualification, values, timezone),
      %ChangeSetRow{
        action: :attach_award_document,
        member_id: member.id,
        old_value: %{},
        new_value: %{"title" => qualification.title, "created_in_set" => true}
      }
    ]
  end

  @doc "The row that attaches the file to an award D4H already has, with its dates."
  def attach(%Member{} = member, %Qualification{} = qualification, award) do
    %ChangeSetRow{
      action: :attach_award_document,
      member_id: member.id,
      old_value: %{},
      new_value: %{
        "title" => qualification.title,
        "d4h_award_id" => award.d4h_award_id,
        "starts_at" => ApplyChangeSet.iso(award.starts_at),
        "ends_at" => ApplyChangeSet.iso(award.ends_at)
      }
    }
  end

  defp apply_set(team, set, user, now, current, bytes) do
    document = %{bytes: bytes, filename: current.file_name, content_type: current.content_type}

    case ApplyChangeSet.call(team, set, user, now, document: document) do
      {:ok, rows} -> {:ok, rows}
      {:error, :no_team_key} -> {:error, "Save your team's access key in team settings first."}
      {:error, error} -> {:error, D4H.error_text(team, error)}
    end
  end

  @doc """
  Pure. How the set went, from all its rows: `{:accepted, d4h_award_id, d4h_document_id}`,
  `{:award_only, d4h_award_id, error}` when the upload did not go, or `{:not_sent, error}`.
  """
  def outcome(rows) do
    award = Enum.find(rows, &(&1.action == :award_qualification))
    document = Enum.find(rows, &(&1.action == :attach_award_document))
    award_id = document.new_value["d4h_award_id"] || applied_id(award)

    cond do
      document.status == :applied -> {:accepted, award_id, document.d4h_record_id}
      award_id -> {:award_only, award_id, document.error}
      true -> {:not_sent, award.error}
    end
  end

  defp applied_id(%ChangeSetRow{status: :applied, d4h_record_id: id}), do: id
  defp applied_id(_row), do: nil

  defp finish(rows, current, user, now) do
    case outcome(rows) do
      {:accepted, award_id, document_id} ->
        accepted(current, dates(rows), award_id, document_id, user, now)

      {:award_only, award_id, error} ->
        current |> Ecto.Changeset.change(d4h_award_id: award_id) |> Repo.update!()

        {:error, "The award was sent, but the certificate did not upload. #{error}"}

      {:not_sent, error} ->
        {:error, error}
    end
  end

  # The award's dates: the new award's, or those of the one D4H had.
  defp dates(rows) do
    row =
      Enum.find(rows, &(&1.action == :award_qualification)) ||
        Enum.find(rows, &(&1.action == :attach_award_document))

    {time(row.new_value["starts_at"]), time(row.new_value["ends_at"])}
  end

  defp accepted(current, dates, award_id, document_id, user, now) do
    Repo.transaction(fn ->
      accepted =
        current
        |> Ecto.Changeset.change(
          status: :accepted,
          decided_by_user_id: user.id,
          decided_at: now,
          d4h_award_id: award_id,
          d4h_document_id: document_id
        )
        |> Repo.update!()

      CertificateFile.delete!(accepted)
      put_award(accepted, dates, award_id, document_id)
      accepted
    end)
  end

  # Into the copy now; the next refresh finds it there and leaves it as it is.
  defp put_award(certificate, {starts_at, ends_at}, award_id, document_id) do
    award =
      MemberQualificationAward.get_by(member_id: certificate.member_id, d4h_award_id: award_id) ||
        MemberQualificationAward.insert!(%{
          member_id: certificate.member_id,
          qualification_id: certificate.qualification_id,
          d4h_award_id: award_id,
          starts_at: starts_at,
          ends_at: ends_at
        })

    MemberQualificationAward
    |> where(id: ^award.id)
    |> Repo.update_all(set: [d4h_document_id: document_id])
  end

  defp time(nil), do: nil

  defp time(iso) do
    {:ok, datetime, 0} = DateTime.from_iso8601(iso)
    DateTime.truncate(datetime, :second)
  end
end
