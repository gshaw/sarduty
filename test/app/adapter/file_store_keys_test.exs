defmodule App.Adapter.FileStoreKeysTest do
  use ExUnit.Case, async: true

  alias App.Adapter.FileStore

  # A key is made by FileStore.key/5, never by hand (docs/files.md), so every file sits
  # under its owner and its kind's lifecycle applies. A string that starts a key outside
  # FileStore fails here.
  @by_hand ~r/["'](teams|orgs|site)\//

  test "no key is built by hand outside FileStore" do
    hits =
      for path <- Path.wildcard("lib/**/*.{ex,exs,heex}"),
          path != "lib/app/adapter/file_store.ex",
          {line, number} <- path |> File.read!() |> String.split("\n") |> Enum.with_index(1),
          Regex.match?(@by_hand, line),
          do: "#{path}:#{number}: #{String.trim(line)}"

    assert hits == [], "Make these keys with FileStore.key/5:\n" <> Enum.join(hits, "\n")
  end

  test "every kind has a row in docs/files.md, with its owner and expiry tag" do
    rows = "docs/files.md" |> File.read!() |> String.split("\n")

    for {kind, %{folder: folder, owner: owner, expires: expires}} <- FileStore.kinds() do
      row = Enum.find(rows, &String.starts_with?(&1, "| `#{folder}`"))
      assert row, "docs/files.md has no row for #{kind}: | `#{folder}` | …"
      assert row =~ "`#{owner}`", "docs/files.md's #{folder} row doesn't name its owner, #{owner}"

      if expires,
        do:
          assert(row =~ "`expires=#{expires}`", "#{folder}'s row doesn't say expires=#{expires}")
    end
  end
end
