defmodule App.CleanUpStandIn do
  @moduledoc """
  Turns Clean up on for one test (#1031), as its stand-in: App.Adapter.CleanUp is off
  everywhere else, as in production. It changes the app's config, so only a test that
  is not async may call it.

  `turn_on/0` runs the stand-in as dev does: a centred square and 1 face. `turn_on/1`
  takes the adapter's test settings: `answer:`, a function of the photo and its kind
  that answers in the stand-in's place, and `timeout:`, how long the adapter waits.
  `found/2` is an answer for a test to give.
  """

  alias App.Adapter.CleanUp

  def turn_on(opts \\ []) do
    original = Application.get_env(:sarduty, CleanUp, [])
    Application.put_env(:sarduty, CleanUp, Keyword.put(opts, :mode, :stand_in))
    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:sarduty, CleanUp, original) end)
  end

  @doc """
  An answer that found `faces` faces: a 300 × 300 cleaned-up photo, a size no photo
  as taken has in a test, with the face where the oval is, or nowhere with no face.
  """
  def found(faces, face \\ Service.MemberPhoto.oval()) do
    bytes = 300 |> Image.new!(300, color: :white) |> Image.write!(:memory, suffix: ".jpg")
    {:ok, %{bytes: bytes, faces: faces, face: if(faces > 0, do: face)}}
  end
end
