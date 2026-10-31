defmodule App.ViewModel.ActivityFormViewModelTest do
  use ExUnit.Case, async: true

  alias App.ViewModel.ActivityFormViewModel

  defp validate(starts_at, ends_at) do
    ActivityFormViewModel.validate(%ActivityFormViewModel{}, %{
      title: "Chores: Governance / Board, October 2026",
      starts_at: starts_at,
      ends_at: ends_at
    })
  end

  test "a finish at the start is fine, as chore events have (#487)" do
    assert {:ok, form} = validate("2026-10-01T00:00", "2026-10-01T00:00")
    assert form.ends_at == form.starts_at
  end

  test "a finish before the start is refused" do
    assert {:error, changeset} = validate("2026-10-01T01:00", "2026-10-01T00:00")
    assert {"Enter a finish after the start.", _} = changeset.errors[:ends_at]
  end

  @today ~D[2026-11-02]

  test "a template fills its details, its start time today, and the finish from its duration" do
    template = %App.Model.Template{
      id: 7,
      title: "Monday night training",
      activity_kind: "exercise",
      start_time: ~T[19:00:00],
      duration_minutes: 150,
      place: "Hall",
      coordinate: "49.10000,-123.10000",
      hours: "secondary",
      description: "<div>Bring a radio.</div>"
    }

    assert ActivityFormViewModel.template_params(template, @today) == %{
             "template_id" => "7",
             "kind" => "exercise",
             "title" => "Monday night training",
             "starts_at" => "2026-11-02T19:00",
             "ends_at" => "2026-11-02T21:30",
             "place" => "Hall",
             "coordinate" => "49.10000,-123.10000",
             "hours" => "secondary",
             "description" => "<div>Bring a radio.</div>"
           }
  end

  test "a template's duration can run for days, and one with no details fills its name" do
    template = %App.Model.Template{
      id: 7,
      title: "Weekend exercise",
      start_time: ~T[08:00:00],
      duration_minutes: 36 * 60,
      hours: "primary"
    }

    assert ActivityFormViewModel.template_params(template, @today)["ends_at"] ==
             "2026-11-03T20:00"

    assert ActivityFormViewModel.template_params(
             %App.Model.Template{id: 8, title: "Truck 1", hours: "primary"},
             @today
           ) ==
             %{"template_id" => "8", "title" => "Truck 1", "hours" => "primary"}
  end

  test "Finish follows Start by the template's length, and stays as typed without one" do
    params = %{"starts_at" => "2026-11-09T19:00", "ends_at" => "2026-11-02T21:30"}
    template = %App.Model.Template{id: 7, title: "Training", duration_minutes: 150}

    assert ActivityFormViewModel.follow_start(params, template)["ends_at"] == "2026-11-09T21:30"

    assert ActivityFormViewModel.follow_start(params, %{template | duration_minutes: nil}) ==
             params

    assert ActivityFormViewModel.follow_start(%{params | "starts_at" => ""}, template)["ends_at"] ==
             "2026-11-02T21:30"
  end
end
