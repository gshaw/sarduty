defmodule App.Operation.LoadActivityPhoto do
  @moduledoc """
  One of an activity photo's files, from the file store (#1032), for the route that
  serves it. Who may see the photo is decided before this:
  App.Model.ActivityPhoto.find_visible!/3.
  """

  alias App.Adapter.FileStore
  alias App.Model.ActivityPhoto

  @doc """
  The photo's file of `size`, one of ActivityPhoto.sizes/0, as a JPEG: `{:ok, bytes}`,
  or `:error` when the store has none.
  """
  def call(%ActivityPhoto{} = photo, size) do
    case photo |> ActivityPhoto.key(size) |> FileStore.get() do
      {:ok, bytes} -> {:ok, bytes}
      {:error, _reason} -> :error
    end
  end
end
