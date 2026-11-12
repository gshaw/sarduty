defmodule App.Adapter.FileStoreTest do
  # Not async: one test turns the store off, which is the app's config.
  use ExUnit.Case

  alias App.Adapter.FileStore
  alias App.FileStoreOff

  # The file store (#1032): a folder on disk in dev and tests, and nothing in
  # production until storage in Canada exists.
  defp key(name), do: "teams/#{System.unique_integer([:positive])}/file-store-test/#{name}"

  test "puts a file, gets it back, and deletes it" do
    key = key("a.jpg")
    assert FileStore.available?()
    assert FileStore.get(key) == {:error, :not_found}

    assert FileStore.put(key, "first") == :ok
    assert FileStore.get(key) == {:ok, "first"}

    # A put takes the place of what was there.
    assert FileStore.put(key, "second") == :ok
    assert FileStore.get(key) == {:ok, "second"}

    assert FileStore.delete(key) == :ok
    assert FileStore.get(key) == {:error, :not_found}
    # One that is gone already is fine.
    assert FileStore.delete(key) == :ok
  end

  test "delete_all/1 takes every file under a prefix, and leaves a prefix that starts the same" do
    team = System.unique_integer([:positive])
    kept = "teams/#{team}0/photos/a.jpg"

    for key <- ["teams/#{team}/photos/a.jpg", "teams/#{team}/photos/deep/b.jpg", kept],
        do: :ok = FileStore.put(key, "bytes")

    assert FileStore.delete_all("teams/#{team}") == :ok

    assert FileStore.get("teams/#{team}/photos/a.jpg") == {:error, :not_found}
    assert FileStore.get("teams/#{team}/photos/deep/b.jpg") == {:error, :not_found}
    assert FileStore.get(kept) == {:ok, "bytes"}
    # A prefix with nothing under it is fine.
    assert FileStore.delete_all("teams/#{team}") == :ok
  end

  test "refuses a key that could leave the store's folder" do
    for key <- [
          "../outside.jpg",
          "teams/../../outside.jpg",
          "/etc/passwd",
          "teams//a.jpg",
          "",
          "a b.jpg"
        ] do
      assert FileStore.put(key, "bytes") == {:error, :invalid_key}, key
      assert FileStore.get(key) == {:error, :invalid_key}, key
      assert FileStore.delete(key) == {:error, :invalid_key}, key
      assert FileStore.delete_all(key) == {:error, :invalid_key}, key
    end
  end

  test "with no store configured, it is not available and every call says so" do
    key = key("off.jpg")
    :ok = FileStore.put(key, "bytes")

    FileStoreOff.turn_off()

    refute FileStore.available?()
    assert FileStore.put(key, "bytes") == {:error, :off}
    assert FileStore.get(key) == {:error, :off}
    assert FileStore.delete(key) == {:error, :off}
    assert FileStore.delete_all("teams") == {:error, :off}
  end
end
