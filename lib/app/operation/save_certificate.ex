defmodule App.Operation.SaveCertificate do
  @moduledoc """
  A member sends a certificate (#493), changes or deletes it while it waits, or deletes
  it once declined; a team admin declines one with a reason the member sees. Accepting is
  App.Operation.AcceptCertificate. Nothing here calls D4H.

  Each change reads the certificate again in its transaction, since a team admin may have
  decided it since the page loaded it.
  """

  alias App.Accounts.User
  alias App.Model.Certificate
  alias App.Model.CertificateFile
  alias App.Model.Member
  alias App.Model.Qualification
  alias App.Model.Team
  alias App.Repo

  @doc """
  A member sends a certificate. `file` is `%{bytes:, file_name:}` from the upload, or nil.
  `{:ok, certificate}` or `{:error, changeset}`, with a file's problem on `:file_name`.
  """
  def send(%Member{} = member, params, file) do
    changeset =
      %Certificate{team_id: member.team_id, member_id: member.id}
      |> Certificate.build_changeset(params, qualification_ids(member.team_id))

    with {:ok, prepared} <- prepare(changeset, file || :missing) do
      transaction(fn ->
        changeset |> put_file(prepared) |> Repo.insert() |> keep_file(prepared)
      end)
    end
  end

  @doc """
  A member changes their certificate while it waits; a nil `file` keeps the one sent.
  `{:error, :decided}` once a team admin has decided it or started sending it.
  """
  def change_own(%Member{} = member, %Certificate{} = certificate, params, file) do
    transaction(fn ->
      with {:ok, current} <- own_now(member, certificate, &Certificate.member_can_change?/1),
           changeset =
             Certificate.build_changeset(current, params, qualification_ids(member.team_id)),
           {:ok, prepared} <- prepare(changeset, file || :keep) do
        changeset |> put_file(prepared) |> Repo.update() |> keep_file(prepared)
      end
    end)
  end

  defp keep_file({:ok, certificate}, %{bytes: bytes}) do
    CertificateFile.put!(certificate, bytes)
    {:ok, certificate}
  end

  defp keep_file(result, _prepared), do: result

  @doc """
  A member deletes their certificate while it waits, or once declined. `:ok`, or
  `{:error, :decided}` once a team admin has accepted it or started sending it.
  """
  def delete_own(%Member{} = member, %Certificate{} = certificate) do
    result =
      transaction(fn ->
        with {:ok, current} <- own_now(member, certificate, &Certificate.member_can_delete?/1),
             do: Repo.delete(current)
      end)

    with {:ok, _certificate} <- result, do: :ok
  end

  @doc """
  A team admin declines a waiting certificate with a reason the member sees, and its
  file is deleted. `{:ok, certificate}`, `{:error, changeset}`, or `{:error, :decided}`.
  """
  def decline(%Team{} = team, %Certificate{team_id: team_id} = certificate, reason, user, now)
      when team_id == team.id and is_struct(user, User) do
    transaction(fn ->
      case Repo.get_by(Certificate, id: certificate.id, team_id: team.id) do
        %Certificate{status: :waiting} = current -> decline_now(current, reason, user, now)
        _decided -> {:error, :decided}
      end
    end)
  end

  defp decline_now(current, reason, user, now) do
    with {:ok, declined} <-
           current |> Certificate.decline_changeset(reason, user, now) |> Repo.update() do
      CertificateFile.delete!(declined)
      {:ok, declined}
    end
  end

  # The file ready to keep: `:missing` on a new certificate is an error, `:keep` keeps
  # the one sent. A bad changeset waits for its other errors to be fixed first.
  defp prepare(changeset, :missing),
    do: {:error, file_error(changeset, "Choose a photo or a PDF of the certificate.")}

  defp prepare(_changeset, :keep), do: {:ok, nil}

  defp prepare(changeset, %{bytes: bytes, file_name: file_name}) do
    case Service.CertificateFile.prepare(bytes, file_name) do
      {:ok, prepared} -> {:ok, prepared}
      {:error, text} -> {:error, file_error(changeset, text)}
    end
  end

  defp file_error(changeset, text),
    do: %{Ecto.Changeset.add_error(changeset, :file_name, text) | action: :insert}

  defp put_file(changeset, nil), do: changeset

  defp put_file(changeset, prepared) do
    Ecto.Changeset.change(changeset,
      file_name: prepared.file_name,
      content_type: prepared.content_type,
      file_size: byte_size(prepared.bytes)
    )
  end

  defp own_now(member, certificate, allowed?) do
    current =
      Repo.get_by(Certificate, id: certificate.id, team_id: member.team_id, member_id: member.id)

    if current && allowed?.(current), do: {:ok, current}, else: {:error, :decided}
  end

  defp transaction(fun) do
    case Repo.transaction(fn -> fun.() |> ok_or_rollback() end) do
      {:ok, value} -> {:ok, value}
      {:error, error} -> {:error, error}
    end
  end

  defp ok_or_rollback({:ok, value}), do: value
  defp ok_or_rollback({:error, error}), do: Repo.rollback(error)

  @doc "The qualifications a certificate can be for: every one the team has in D4H."
  def qualification_ids(team_id), do: team_id |> Qualification.get_all() |> Enum.map(& &1.id)
end
