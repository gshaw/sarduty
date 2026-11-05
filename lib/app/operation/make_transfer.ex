defmodule App.Operation.MakeTransfer do
  @moduledoc """
  Makes a transfer code (#892): copies the awards a team admin picked, and their
  certificates, from the team's own D4H now, with the team's own key. The receiving team
  adds them from the copy and never reads this team's D4H.

  D4H is read fresh, so the copy has the dates D4H has now, not the last refresh's. An
  award D4H no longer has stops the code being made, rather than leaving it out quietly:
  "What will be transferred" must be what the team admin picked.
  """

  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Model.Team
  alias App.Model.Transfer
  alias App.Model.TransferAward
  alias App.Model.TransferAwardFile
  alias App.Operation.LoadCertificate
  alias App.Operation.RefreshD4HData.UpsertAwardDocuments
  alias App.Repo
  alias App.ViewData.MemberRecords

  @doc """
  The awards a transfer can carry: the member's latest award of each qualification, as
  the member's Qualifications tab lists them, `%{award:, status:}` rows. An expired one
  goes only if picked.
  """
  def offered(%Member{} = member, now), do: MemberRecords.qualifications(member, now)

  @doc """
  `{:ok, transfer}` with its awards, or `{:error, text}` for the team admin. `award_ids`
  are local ids from `offered/2`; any other id is ignored.
  """
  def call(%Team{} = team, %Member{team_id: team_id} = member, award_ids, %User{} = user, now)
      when team_id == team.id do
    picked = picked(offered(member, now), award_ids)

    cond do
      picked == [] ->
        {:error, "Select at least 1 award."}

      is_nil(team.d4h_access_key) ->
        {:error, "Save your team's access key in team settings first."}

      true ->
        copy(team, member, picked, user, now)
    end
  end

  defp copy(team, member, picked, user, now) do
    d4h = D4H.build_context_from_team(team)

    with {:ok, planned} <- plan(picked, D4H.fetch_member_awards(d4h, member.d4h_member_id)),
         {:ok, planned} <- fetch_files(d4h, planned) do
      insert(member, planned, user, now)
    else
      {:error, {:changed, title}} ->
        {:error, "#{title} has changed since this page opened. Open the page again to see it."}

      {:error, %D4H.Error{} = error} ->
        {:error, D4H.error_text(team, error)}
    end
  rescue
    error in [D4H.Error, Req.TransportError] -> {:error, D4H.error_text(team, error)}
  end

  @doc """
  Pure. The picked awards with D4H's dates now: `{:ok, [%{position:, award:, d4h:}]}` in
  the order given, or `{:error, {:changed, title}}` for the first one D4H no longer has.
  `picked` are local awards with their qualification; `d4h_awards` the member's
  D4H.QualificationAward list.
  """
  def plan(picked, d4h_awards) do
    by_id = Map.new(d4h_awards, &{&1.d4h_award_id, &1})

    picked
    |> Enum.with_index(1)
    |> map_while_ok(fn {award, position} ->
      case Map.fetch(by_id, award.d4h_award_id) do
        {:ok, d4h} -> {:ok, %{position: position, award: award, d4h: d4h}}
        :error -> {:error, {:changed, award.qualification.title}}
      end
    end)
  end

  # `{:ok, mapped}` in order, or the first `{:error, _}` the function returns.
  defp map_while_ok(list, fun) do
    result =
      Enum.reduce_while(list, {:ok, []}, fn item, {:ok, acc} ->
        case fun.(item) do
          {:ok, value} -> {:cont, {:ok, [value | acc]}}
          error -> {:halt, error}
        end
      end)

    with {:ok, values} <- result, do: {:ok, Enum.reverse(values)}
  end

  @doc "Pure. The picked awards among the offered rows, in the rows' order."
  def picked(rows, award_ids) do
    ids = MapSet.new(award_ids, &to_string/1)
    rows |> Enum.map(& &1.award) |> Enum.filter(&MapSet.member?(ids, to_string(&1.id)))
  end

  # Each award's certificate, the newest document on it, as the sync picks it.
  defp fetch_files(d4h, planned) do
    map_while_ok(planned, fn row ->
      with {:ok, file} <- fetch_file(d4h, row), do: {:ok, Map.put(row, :file, file)}
    end)
  end

  defp fetch_file(d4h, %{d4h: award} = row) do
    documents = D4H.fetch_award_documents(d4h, award.d4h_award_id)
    newest = UpsertAwardDocuments.newest(documents)

    case Map.get(newest, award.d4h_award_id) do
      nil ->
        {:ok, nil}

      document_id ->
        case D4H.fetch_document(d4h, document_id) do
          {:ok, bytes, content_type} ->
            type = LoadCertificate.media_type(content_type)
            name = LoadCertificate.filename(row.award.qualification.title, type)
            {:ok, %{bytes: bytes, content_type: type, file_name: name}}

          {:error, response} ->
            {:error, D4H.Error.exception(response)}
        end
    end
  end

  defp insert(member, planned, user, now) do
    code = Transfer.generate_code()

    Repo.transact(fn ->
      transfer =
        Repo.insert!(%Transfer{
          team_id: member.team_id,
          member_id: member.id,
          made_by_user_id: user.id,
          code: code,
          code_hash: Transfer.code_hash(code),
          member_name: member.name,
          member_email: member.email,
          expires_at: Transfer.expires_at(now)
        })

      Enum.each(planned, &insert_award(transfer, &1))
      {:ok, Repo.preload(transfer, :awards)}
    end)
  end

  defp insert_award(transfer, %{position: position, award: award, d4h: d4h, file: file}) do
    record =
      Repo.insert!(%TransferAward{
        team_id: transfer.team_id,
        transfer_id: transfer.id,
        position: position,
        qualification_title: award.qualification.title,
        d4h_qualification_id: award.qualification.d4h_qualification_id,
        organization_owned: award.qualification.organization_owned,
        starts_at: whole_seconds(d4h.starts_at),
        ends_at: whole_seconds(d4h.ends_at)
      })

    if file do
      record
      |> Ecto.Changeset.change(
        file_name: file.file_name,
        content_type: file.content_type,
        file_size: byte_size(file.bytes)
      )
      |> Repo.update!()

      Repo.insert!(%TransferAwardFile{transfer_award_id: record.id, bytes: file.bytes})
    end
  end

  defp whole_seconds(nil), do: nil
  defp whole_seconds(datetime), do: DateTime.truncate(datetime, :second)
end
