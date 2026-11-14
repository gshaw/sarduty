defmodule App.Operation.CleanUpPhoto do
  @moduledoc """
  Clean up for one photo (#1031), while the person waits on Add a photo. It asks
  App.Adapter.CleanUp for the cleaned-up photo, then works out what the page shows with
  it: where the photo starts in the square, and what to warn about. SAR Duty warns and
  never blocks, so a warning changes no button's work.
  """

  alias App.Adapter.CleanUp

  @doc "Whether Clean up runs at all. With it off, no page mentions it."
  def available?, do: CleanUp.available?()

  @doc """
  `photo` is `%{bytes:}` from Service.MemberPhoto.prepare/1, and `kind` what it is, as
  the adapter takes it. `{:ok, %{cleaned:, placed:, warnings:}}`: the cleaned-up photo
  as `%{bytes:, width:, height:}`, where it starts in the square, as
  Service.MemberPhoto.placement/1 gives one, and `warnings/2`. `{:error, reason}` when
  Clean up did not answer, or sent a photo that cannot be read.
  """
  def call(%{bytes: bytes}, kind) when is_binary(bytes) do
    with {:ok, %{bytes: cleaned, faces: faces, face: face}} <- CleanUp.call(bytes, kind),
         {:ok, image} <- Image.from_binary(cleaned) do
      {width, height} = {Image.width(image), Image.height(image)}

      {:ok,
       %{
         cleaned: %{bytes: cleaned, width: width, height: height},
         placed: Service.MemberPhoto.face_placement({width, height}, face),
         warnings: warnings(faces, Service.MemberPhoto.dark?(bytes))
       }}
    end
  end

  @doc """
  Pure. What to warn about, in the order the page lists it: `{:faces, count}` for more
  than 1 face or `:no_face` for none, then `:dark`. Only what SAR Duty can tell for
  sure: sunglasses and hats are a team admin's to decline.
  """
  def warnings(faces, dark?) when is_integer(faces) and is_boolean(dark?) do
    found =
      cond do
        faces > 1 -> [{:faces, faces}]
        faces == 0 -> [:no_face]
        true -> []
      end

    found ++ if(dark?, do: [:dark], else: [])
  end
end
