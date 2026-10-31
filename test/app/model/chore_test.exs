defmodule App.Model.ChoreTest do
  use ExUnit.Case, async: true

  alias App.Accounts.User
  alias App.Model.Chore

  @today ~D[2026-11-05]
  @params %{
    "date" => "2026-10-28",
    "time" => "1h",
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

  test "the time is more than 0 and up to a day, and the category is one it may have" do
    changeset = Chore.build_changeset(%Chore{}, @params, [7], @today)
    assert Ecto.Changeset.get_change(changeset, :minutes) == 60

    assert errors(%{"time" => "0"}) == [time: "Enter a time over 0"]
    assert errors(%{"time" => "25h"}) == [time: "Enter up to 24h"]
    assert errors(%{"time" => "30.5"}) == [time: "Enter up to 24h"]
    assert errors(%{"time" => "soon"}) == [time: "Enter the time like 45m, 2h, or 2.5h"]
    assert errors(%{"time" => " "}) == [time: "Enter how long it took"]
    assert errors(%{"chore_category_id" => "8"}) == [chore_category_id: "Select a category"]
  end

  test "a changed chore keeps its minutes until its time is sent, and a cleared time is an error" do
    chore = %Chore{minutes: 90, time: "1h 30m"}

    assert Chore.build_changeset(chore, %{"date" => "2026-10-28"}, [7], @today).changes == %{
             date: ~D[2026-10-28]
           }

    changeset = Chore.build_changeset(%Chore{minutes: 90}, %{"time" => ""}, [7], @today)
    assert changeset.errors[:time] == {"Enter how long it took", []}
  end

  test "what they did is one line, its spaces squeezed" do
    params = Map.put(@params, "description", "Radio\n  programming")
    changeset = Chore.build_changeset(%Chore{}, params, [7], @today)
    assert Ecto.Changeset.get_change(changeset, :description) == "Radio programming"
  end

  test "errors come in the form's order" do
    fields = %{"date" => "", "description" => "", "time" => ""} |> errors() |> Keyword.keys()
    assert fields == [:description, :date, :time]
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
