defmodule App.ViewModel.HelpFormViewModelTest do
  use ExUnit.Case, async: true

  alias App.ViewModel.HelpFormViewModel

  defp validate(params, contacts?),
    do: HelpFormViewModel.validate(%HelpFormViewModel{}, params, contacts?)

  test "starts with the team ticked, or the site admins when the team has no contacts" do
    assert HelpFormViewModel.new(true).to == ["team"]
    assert HelpFormViewModel.new(false).to == ["site_admins"]
  end

  test "keeps what was ticked, with the message trimmed" do
    assert {:ok, %{to: ["team", "site_admins"], message: "Hours show 0."}} =
             validate(
               %{"to" => ["", "team", "site_admins"], "message" => "  Hours show 0.\r\n"},
               true
             )
  end

  test "never sends to a team with no contacts, so nothing falls back to every team admin" do
    assert {:error, changeset} = validate(%{"to" => ["", "team"], "message" => "Hi"}, false)
    assert {"Select who to send it to", _} = changeset.errors[:to]

    assert {:ok, %{to: ["site_admins"]}} =
             validate(%{"to" => ["team", "site_admins"], "message" => "Hi"}, false)
  end

  test "needs a message, and not too long a one" do
    assert {:error, changeset} = validate(%{"to" => ["team"], "message" => " "}, true)
    assert {"Enter a message", _} = changeset.errors[:message]

    assert {:error, changeset} =
             validate(%{"to" => ["team"], "message" => String.duplicate("a", 2001)}, true)

    assert {"Enter a message of 2,000 characters or fewer", _} = changeset.errors[:message]
  end
end
