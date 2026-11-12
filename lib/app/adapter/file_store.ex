defmodule App.Adapter.FileStore do
  @moduledoc """
  Where SAR Duty keeps files that are too big for the database (#1032): an activity's
  photos today. Files never go in SQLite, which Litestream copies whole. This module is
  the only place that knows where they are. Callers put, get, and delete by key, and
  `delete_all/1` takes every file under a prefix, for a team that is deleted.

  `config :sarduty, App.Adapter.FileStore` picks the store:

  - Nothing, the default and what production runs: no store. `available?/0` is false,
    every call answers `{:error, :off}`, and whatever needs files is not offered.
  - `dir:`, a folder on disk, for dev and tests (config/dev.exs, config/test.exs). A key
    is the file's path under it.
  - Storage in Canada, later, in its own issue: a clause of each function below, picked
    by its own setting, and nothing else changes. No AWS key, library, or account until
    then.

  A key is made here in the app, never from what a person typed: `teams/12/…`, in
  letters, digits, `.`, `_`, `-`, and `/`. Anything else is refused, so a key can never
  leave the store's folder.
  """

  # cspell:ignore enoent -- the file system's "no such file", as File's functions name it

  @doc "Whether there is a store at all. False in production until storage in Canada exists."
  def available?, do: dir() != nil

  @doc "Keeps `bytes` at `key`, in place of what was there. `:ok` or `{:error, reason}`."
  def put(key, bytes) when is_binary(key) and is_binary(bytes) do
    # Written beside it and moved into place, so a read never gets half a file.
    with {:ok, path} <- path(key),
         partial = "#{path}.#{System.unique_integer([:positive])}.part",
         :ok <- path |> Path.dirname() |> File.mkdir_p(),
         :ok <- File.write(partial, bytes) do
      File.rename(partial, path)
    end
  end

  @doc "The file at `key`: `{:ok, bytes}`, `{:error, :not_found}`, or `{:error, reason}`."
  def get(key) when is_binary(key) do
    with {:ok, path} <- path(key) do
      case File.read(path) do
        {:ok, bytes} -> {:ok, bytes}
        {:error, :enoent} -> {:error, :not_found}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc "Deletes the file at `key`. One that is not there is `:ok` too."
  def delete(key) when is_binary(key) do
    with {:ok, path} <- path(key) do
      case File.rm(path) do
        :ok -> :ok
        {:error, :enoent} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Deletes every file whose key starts with `prefix` and a slash: `teams/12` takes
  `teams/12/…` and leaves `teams/123/…`. `:ok` when there were none.
  """
  def delete_all(prefix) when is_binary(prefix) do
    with {:ok, path} <- path(prefix) do
      case File.rm_rf(path) do
        {:ok, _removed} -> :ok
        {:error, reason, _file} -> {:error, reason}
      end
    end
  end

  # The file a key names, inside the store's folder.
  defp path(key) do
    cond do
      dir() == nil -> {:error, :off}
      valid?(key) -> {:ok, Path.join(dir(), key)}
      true -> {:error, :invalid_key}
    end
  end

  # Segments of letters, digits, `.`, `_`, and `-`, split by single slashes, and none
  # that is only dots.
  defp valid?(key) do
    segments = String.split(key, "/")

    segments != [] and
      Enum.all?(segments, &(&1 =~ ~r/\A[A-Za-z0-9._-]+\z/ and not (&1 =~ ~r/\A\.+\z/)))
  end

  defp dir, do: Application.get_env(:sarduty, __MODULE__, [])[:dir]
end
