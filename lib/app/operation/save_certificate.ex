defmodule App.Operation.SaveCertificate do
  @moduledoc """
  A member sends a certificate (#493), changes or deletes it while it waits, or deletes
  it once declined; a team admin declines one with a reason the member sees, or turns its
  photo. Accepting is App.Operation.AcceptCertificate. Nothing here calls D4H.

  Each change reads the certificate again in its transaction, since a team admin may have
  decided it since the page loaded it. Each also waits for an accept that is sending it
  (`locked/2`).
  """

  alias App.Accounts.User
  alias App.Model.Certificate
  alias App.Model.CertificateFile
  alias App.Model.Member
  alias App.Model.Qualification
  alias App.Model.Team
  alias App.Repo

  @missing_file "Select a photo or a PDF of the certificate."

  @doc """
  A member sends a certificate. `file` is `%{bytes:, file_name:}` from the upload, or nil.
  `{:ok, certificate}` or `{:error, changeset}`, with a file's problem on `:file_name`.
  """
  def send(%Member{} = member, params, file) do
    changeset =
      %Certificate{team_id: member.team_id, member_id: member.id}
      |> Certificate.member_changeset(params, qualification_ids(member.team_id))

    with {:ok, prepared} <- (file || :missing) |> prepare() |> on_changeset(changeset) do
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
    prepared = prepare(file || :keep)

    locked_transaction(certificate, fn ->
      with {:ok, current} <- own_now(member, certificate, &Certificate.member_can_change?/1),
           changeset =
             Certificate.member_changeset(current, params, qualification_ids(member.team_id)),
           {:ok, prepared} <- on_changeset(prepared, changeset) do
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
      locked_transaction(certificate, fn ->
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
    locked_transaction(certificate, fn ->
      case Repo.get_by(Certificate, id: certificate.id, team_id: team.id) do
        %Certificate{status: :waiting} = current -> decline_now(current, reason, user, now)
        _decided -> {:error, :decided}
      end
    end)
  end

  @doc """
  A team admin turns a waiting certificate's photo a quarter, `:left` or `:right`, so it
  goes to D4H the right way up. `{:ok, certificate}`, `{:error, :decided}`, or
  `{:error, :not_a_photo}` for a PDF.
  """
  def rotate(%Team{} = team, %Certificate{team_id: team_id} = certificate, direction)
      when team_id == team.id do
    # Turned under the lock but outside a transaction, which would hold SQLite's write
    # lock while the photo decodes (#385).
    locked(certificate, fn -> rotate_now(team, certificate, direction) end)
  end

  defp rotate_now(team, certificate, direction) do
    with {:ok, current} <- waiting_photo(team, certificate),
         bytes = CertificateFile.bytes(current),
         {:ok, turned} <- Service.CertificateFile.rotate(bytes, direction),
         do: transaction(fn -> put_turned(current, turned) end)
  end

  defp put_turned(current, turned) do
    CertificateFile.put!(current, turned)

    current
    |> Ecto.Changeset.change(file_size: byte_size(turned), updated_at: DateTime.utc_now())
    |> Repo.update()
  end

  defp waiting_photo(team, certificate) do
    case Repo.get_by(Certificate, id: certificate.id, team_id: team.id) do
      %Certificate{status: :waiting, content_type: "image/jpeg"} = current -> {:ok, current}
      %Certificate{status: :waiting} -> {:error, :not_a_photo}
      _decided -> {:error, :decided}
    end
  end

  @doc """
  Runs `fun` while nothing else changes the certificate: an accept, a member's change or
  delete, or a decline. An accept holds it while it waits on D4H, so the others read the
  certificate only once it is done. Take it before a transaction, never inside one: a
  transaction waiting here would hold SQLite's write lock that the accept needs.
  """
  def locked(%Certificate{id: id}, fun), do: :global.trans({{Certificate, id}, self()}, fun)

  defp decline_now(current, reason, user, now) do
    with {:ok, declined} <-
           current |> Certificate.decline_changeset(reason, user, now) |> Repo.update() do
      CertificateFile.delete!(declined)
      {:ok, declined}
    end
  end

  # The file ready to keep, before any transaction: a photo's resize would hold SQLite's
  # write lock (#385). `:missing` on a new certificate is an error, `:keep` keeps the one
  # sent.
  defp prepare(:missing), do: {:error, @missing_file}
  defp prepare(:keep), do: {:ok, nil}

  defp prepare(%{bytes: bytes, file_name: file_name}),
    do: Service.CertificateFile.prepare(bytes, file_name)

  @doc """
  The form's changeset with the missing file's error, so a new certificate sent with no
  file says so beside its other mistakes, not after they are fixed.
  """
  def missing_file(changeset),
    do: %{Ecto.Changeset.add_error(changeset, :file_name, @missing_file) | action: :insert}

  # A file's problem goes on the changeset, for the form.
  defp on_changeset({:ok, prepared}, _changeset), do: {:ok, prepared}

  defp on_changeset({:error, text}, changeset),
    do: {:error, %{Ecto.Changeset.add_error(changeset, :file_name, text) | action: :insert}}

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

  # The lock first, then the transaction: never the other way (locked/2).
  defp locked_transaction(certificate, fun),
    do: locked(certificate, fn -> transaction(fun) end)

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
