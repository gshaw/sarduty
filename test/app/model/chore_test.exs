defmodule App.Model.ChoreTest do
  use ExUnit.Case, async: true

  alias App.Accounts.User
  alias App.Model.Chore

  @today ~D[2026-11-05]
  @params %{
    "date" => "2026-10-28",
    "minutes" => "60",
    "chore_category_id" => "7",
    "description" => " Truck 2 tire pressures "
  }

  defp errors(params, who \\ :member) do
    %Chore{}
    |> Chore.build_changeset(Map.merge(@params, params), [7], @today, who)
    |> Map.fetch!(:errors)
    |> Enum.map(fn {field, {message, _opts}} -> {field, message} end)
  end

  test "a member logs a chore from the last 60 days, trimmed" do
    changeset = Chore.build_changeset(%Chore{}, @params, [7], @today)
    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :description) == "Truck 2 tire pressures"
    assert errors(%{"date" => "2026-09-06"}) == []
  end

  test "a member cannot log a chore from the future, or more than 60 days ago" do
    assert errors(%{"date" => "2026-11-06"}) == [date: "Enter a date that has passed"]
    assert errors(%{"date" => "2026-09-05"}) == [date: "Enter a date in the last 60 days"]
  end

  test "a team admin sets any date that has passed" do
    assert errors(%{"date" => "2020-01-01"}, :team_admin) == []

    assert errors(%{"date" => "2026-11-06"}, :team_admin) == [
             date: "Enter a date that has passed"
           ]
  end

  test "minutes are 1 to a day, and the category is one it may have" do
    assert errors(%{"minutes" => "0"}) == [minutes: "Enter minutes from 1 to 1440"]
    assert errors(%{"minutes" => "1441"}) == [minutes: "Enter minutes from 1 to 1440"]
    assert errors(%{"chore_category_id" => "8"}) == [chore_category_id: "Select a category"]
  end

  test "errors come in the form's order" do
    fields = %{"date" => "", "description" => "", "minutes" => ""} |> errors() |> Keyword.keys()
    assert fields == [:date, :minutes, :description]
  end

  test "declining needs a reason; accepting clears an old one" do
    user = %User{id: 1}
    now = ~U[2026-11-05 12:00:00Z]

    refute Chore.decide_changeset(%Chore{}, :declined, user, now, " ").valid?

    accepted = Chore.decide_changeset(%Chore{decline_reason: "No"}, :accepted, user, now)
    assert accepted.valid?
    assert Ecto.Changeset.get_field(accepted, :decline_reason) == nil
  end
end
