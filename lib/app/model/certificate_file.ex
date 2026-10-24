defmodule App.Model.CertificateFile do
  use App, :model

  alias App.Model.Certificate
  alias App.Model.CertificateFile
  alias App.Repo

  # A waiting certificate's file (#493), apart from the certificate so lists never load
  # it. A photo is already re-encoded with its metadata gone (Service.CertificateFile).
  # Deleted once the certificate is in D4H or declined.
  schema "certificate_files" do
    belongs_to :certificate, Certificate
    field :bytes, :binary, redact: true
  end

  @doc "Sets the certificate's file, replacing any it had."
  def put!(%Certificate{id: id}, bytes) when is_binary(bytes) do
    Repo.insert!(%CertificateFile{certificate_id: id, bytes: bytes},
      on_conflict: {:replace, [:bytes]},
      conflict_target: :certificate_id
    )
  end

  @doc "The certificate's file, or nil once it is gone."
  def bytes(%Certificate{id: id}) do
    CertificateFile
    |> where(certificate_id: ^id)
    |> select([f], f.bytes)
    |> Repo.one()
  end

  def delete!(%Certificate{id: id}) do
    CertificateFile |> where(certificate_id: ^id) |> Repo.delete_all()
    :ok
  end
end
