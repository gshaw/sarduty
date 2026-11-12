defmodule App.Model.MemberPhotoFile do
  use App, :model

  alias App.Model.MemberPhoto
  alias App.Model.MemberPhotoFile
  alias App.Repo

  # A waiting photo as the member took it (#1029), kept the way a certificate's file is
  # (CertificateFile): apart from its row so lists never load it, already a JPEG up to
  # 2048 px with its metadata gone (Service.MemberPhoto.prepare/1). With Clean up
  # (#1031) it keeps the cleaned-up photo beside it. Deleted once the photo is accepted
  # or declined.
  schema "member_photo_files" do
    belongs_to :member_photo, MemberPhoto
    field :bytes, :binary, redact: true
    field :cleaned_bytes, :binary, redact: true
  end

  @doc "Keeps the photo's file: as taken, and cleaned up when Clean up answered."
  def put!(%MemberPhoto{id: id}, bytes, cleaned_bytes \\ nil) when is_binary(bytes) do
    Repo.insert!(
      %MemberPhotoFile{member_photo_id: id, bytes: bytes, cleaned_bytes: cleaned_bytes},
      on_conflict: {:replace, [:bytes, :cleaned_bytes]},
      conflict_target: :member_photo_id
    )
  end

  @doc """
  One of the photo's files, `:taken` or `:cleaned`, or nil: once it is gone, or for a
  photo with no cleaned-up copy.
  """
  def bytes(%MemberPhoto{id: id}, shape \\ :taken) when shape in [:taken, :cleaned] do
    MemberPhotoFile
    |> where(member_photo_id: ^id)
    |> select_shape(shape)
    |> Repo.one()
  end

  defp select_shape(query, :taken), do: select(query, [f], f.bytes)
  defp select_shape(query, :cleaned), do: select(query, [f], f.cleaned_bytes)

  def delete!(%MemberPhoto{id: id}) do
    MemberPhotoFile |> where(member_photo_id: ^id) |> Repo.delete_all()
    :ok
  end
end
