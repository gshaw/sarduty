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

  test "a template fills its details, its start time today, and the finish from its length" do
    template = %App.Model.Template{
      id: 7,
      title: "Monday night training",
      activity_kind: "exercise",
      start_time: ~T[19:00:00],
      length_minutes: 150,
      place: "Hall",
      coordinate: "49.10000,-123.10000",
      hours: "secondary",
      description: "<div>Bring a radio.</div>"
    }

    params = ActivityFormViewModel.template_params(%{"tracking_number" => "A1"}, template, @today)

    assert params == %{
             "template_id" => "7",
             "kind" => "exercise",
             "title" => "Monday night training",
             "starts_at" => "2026-11-02T19:00",
             "ends_at" => "2026-11-02T21:30",
             "place" => "Hall",
             "coordinate" => "49.10000,-123.10000",
             "hours" => "secondary",
             "description" => "<div>Bring a radio.</div>",
             "tracking_number" => "A1"
           }
  end

  test "a template's start time goes on the day Start has, and its length can run for days" do
    template = %App.Model.Template{
      id: 7,
      title: "Weekend exercise",
      start_time: ~T[08:00:00],
      length_minutes: 36 * 60,
      hours: "primary"
    }

    params = %{"starts_at" => "2026-11-07T10:15", "ends_at" => "2026-11-07T12:00"}
    params = ActivityFormViewModel.template_params(params, template, @today)

    assert params["starts_at"] == "2026-11-07T08:00"
    assert params["ends_at"] == "2026-11-08T20:00"
  end

  test "a template with no details fills its name and leaves what was typed" do
    template = %App.Model.Template{id: 7, title: "Truck 1", hours: "primary"}
    typed = %{"place" => "Yard", "coordinate" => "49.10000,-123.10000", "starts_at" => "x"}
    params = ActivityFormViewModel.template_params(typed, template, @today)

    assert params ==
             Map.merge(typed, %{"template_id" => "7", "title" => "Truck 1", "hours" => "primary"})
  end

  test "a template's address and pin replace the form's as a pair" do
    typed = %{"place" => "Yard", "coordinate" => "49.10000,-123.10000"}

    address = %App.Model.Template{
      id: 7,
      title: "Boat launch",
      place: "Boat launch",
      hours: "primary"
    }

    pin = %App.Model.Template{
      id: 8,
      title: "Pin",
      coordinate: "49.20000,-123.20000",
      hours: "primary"
    }

    params = ActivityFormViewModel.template_params(typed, address, @today)
    assert {params["place"], params["coordinate"]} == {"Boat launch", ""}
    assert {:ok, form} = ActivityFormViewModel.validate(%ActivityFormViewModel{}, filled(params))
    assert form.coordinate == nil

    params = ActivityFormViewModel.template_params(typed, pin, @today)
    assert {params["place"], params["coordinate"]} == {"", "49.20000,-123.20000"}
  end

  test "Finish follows Start by the template's length, and stays as typed without one" do
    params = %{"starts_at" => "2026-11-09T19:00", "ends_at" => "2026-11-02T21:30"}
    template = %App.Model.Template{id: 7, title: "Training", length_minutes: 150}

    assert ActivityFormViewModel.follow_start(params, template)["ends_at"] == "2026-11-09T21:30"
    assert ActivityFormViewModel.follow_start(params, %{template | length_minutes: nil}) == params

    assert ActivityFormViewModel.follow_start(%{params | "starts_at" => ""}, template)["ends_at"] ==
             "2026-11-02T21:30"
  end

  defp filled(params),
    do: Map.merge(params, %{"starts_at" => "2026-11-02T19:00", "ends_at" => "2026-11-02T21:00"})
end
