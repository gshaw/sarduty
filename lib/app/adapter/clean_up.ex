defmodule App.Adapter.CleanUp do
  @moduledoc """
  Clean up (#1031): removes a photo's background and centres the face. It will run on a
  function in Calgary, which does not exist yet, and this module is the only place that
  will know it. `config :sarduty, App.Adapter.CleanUp, mode:` picks one of three modes:

  - `:off`, the default and what production runs. Clean up is not available, and no
    page mentions it.
  - `:stand_in`, for dev and tests, with no AWS: it cuts the photo to a centred square
    and reports 1 face, where the oval is. A dev turns it on with `CLEAN_UP=stand-in`
    (config/runtime.exs).
  - The function, later, in its own issue: a clause of `answer/3`, and nothing else
    changes.

  The person is waiting, so the call is made inline (docs/jobs.md) and gives up after 30
  seconds. A test gives the stand-in its own answer with `answer:`, a function of the
  photo and its kind, and a shorter wait with `timeout:`.
  """

  # What the photo is: a member's, for their ID card. An activity's comes with #1035.
  @kinds [:member]
  @timeout 30_000

  @doc "Whether Clean up runs at all. False in production until the function exists."
  def available?, do: mode() != :off

  @doc """
  Cleans up `jpeg`, a photo of `kind`. `{:ok, %{bytes:, faces:, face:}}`: the cleaned-up
  photo as a JPEG, how many faces it found, and where the face is in the cleaned-up
  photo, or nil with none: `x` and `y`, its centre, and `width` and `height`, as shares
  of the photo's width and height. `{:error, :off}` when Clean up is not available,
  `{:error, :timeout}` after 30 seconds, or `{:error, reason}`.
  """
  def call(jpeg, kind) when is_binary(jpeg) and kind in @kinds do
    case mode() do
      :off -> {:error, :off}
      mode -> within(config()[:timeout] || @timeout, fn -> answer(mode, jpeg, kind) end)
    end
  end

  # The function goes here, as its own mode: it sends the photo and reads this same
  # answer. No AWS key, library, or account until then.
  defp answer(:stand_in, jpeg, kind), do: (config()[:answer] || (&stand_in/2)).(jpeg, kind)

  defp stand_in(jpeg, :member) do
    with {:ok, image} <- Image.from_binary(jpeg),
         {width, height} = {Image.width(image), Image.height(image)},
         side = min(width, height),
         {:ok, square} <-
           Image.crop(image, div(width - side, 2), div(height - side, 2), side, side),
         {:ok, bytes} <-
           Image.write(square, :memory, suffix: ".jpg", quality: 85, strip_metadata: true) do
      # The face is where Add a photo's oval is, so the square starts whole.
      {:ok, %{bytes: bytes, faces: 1, face: Service.MemberPhoto.oval()}}
    end
  end

  # Runs `fun` for up to `timeout` ms. One that crashes is an error, not this caller's
  # crash.
  defp within(timeout, fun) do
    task =
      Task.async(fn ->
        try do
          fun.()
        rescue
          exception -> {:error, exception}
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, answer} -> answer
      _gave_up -> {:error, :timeout}
    end
  end

  defp mode, do: config()[:mode] || :off

  defp config, do: Application.get_env(:sarduty, __MODULE__, [])
end
