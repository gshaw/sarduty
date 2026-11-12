defmodule App.Model.MemberPhotoFile do
  use App, :model

  alias App.Model.MemberPhoto
  alias App.Model.MemberPhotoFile
  alias App.Repo

  # A waiting photo as the member took it (#1029), kept the way a certificate's file is
  # (CertificateFile): apart from its row so lists never load it, already a JPEG up to
  # 2048 px with its metadata gone (Service.MemberPhoto.prepare/1). Deleted once the
  # photo is accepted or declined.
  schema "member_photo_files" do
    belongs_to :member_photo, MemberPhoto
    field :bytes, :binary, redact: true
  end

  @doc "Keeps the photo's file."
  def put!(%MemberPhoto{id: id}, bytes) when is_binary(bytes) do
    Repo.insert!(%MemberPhotoFile{member_photo_id: id, bytes: bytes},
      on_conflict: {:replace, [:bytes]},
      conflict_target: :member_photo_id
    )
  end

  @doc "The photo's file, or nil once it is gone."
  def bytes(%MemberPhoto{id: id}) do
    MemberPhotoFile
    |> where(member_photo_id: ^id)
    |> select([f], f.bytes)
    |> Repo.one()
  end

  def delete!(%MemberPhoto{id: id}) do
    MemberPhotoFile |> where(member_photo_id: ^id) |> Repo.delete_all()
    :ok
  end
end
