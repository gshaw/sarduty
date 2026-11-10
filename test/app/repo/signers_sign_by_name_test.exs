defmodule App.Repo.SignersSignByNameTest do
  # The migration that makes a signer one line (#995): made-up signers, never a team's.
  use ExUnit.Case, async: true

  @migration App.Repo.Migrations.SignersSignByName

  # Migrating the test database loads it; a run that skipped that loads it here.
  setup_all do
    if !Code.ensure_loaded?(@migration),
      do: Code.require_file("priv/repo/migrations/20261110040000_signers_sign_by_name.exs")

    :ok
  end

  # The module is loaded at run time from its .exs, so a direct call warns as undefined.
  defp split(name, title \\ nil, phone \\ nil, email \\ nil) do
    # credo:disable-for-next-line Credo.Check.Refactor.Apply
    apply(@migration, :split, [[name, title, phone, email]])
  end

  test "a name alone stays as it is" do
    assert split("Alex Chen", "President") == ["Alex Chen", "President", nil, nil]
  end

  test "Name, Title: the title after the comma, only when there's none" do
    assert split("Alex Chen, President") == ["Alex Chen", "President", nil, nil]
    assert split("Alex Chen, President", "Chair") == ["Alex Chen", "Chair", nil, nil]
  end

  test "lines: the title on line 2, an email and a phone to their fields, the rest dropped" do
    name = "Alex Chen\nPresident\n123 Main St\nSquamish BC\n604-555-0112\nalex.chen@example.com"

    assert split(name) == [
             "Alex Chen",
             "President",
             "604-555-0112",
             "alex.chen@example.com"
           ]
  end

  test "a field already set keeps its value" do
    name = "Alex Chen\nPresident\nTel: 604-555-0112\nEmail: alex@example.com"

    assert split(name, "Chair", "604-555-0199", "chair@example.com") ==
             ["Alex Chen", "Chair", "604-555-0199", "chair@example.com"]

    assert split(name) == ["Alex Chen", "President", "604-555-0112", "alex@example.com"]
  end

  test "line 2 that is a phone or an email is not a title" do
    assert split("Alex Chen\n604-555-0112") == ["Alex Chen", nil, "604-555-0112", nil]
    assert split("Alex Chen\nalex@example.com") == ["Alex Chen", nil, nil, "alex@example.com"]
  end
end
