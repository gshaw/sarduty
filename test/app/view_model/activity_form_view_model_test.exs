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

  test "a template fills its details, and the finish from its length" do
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

    params = ActivityFormViewModel.template_params(%{"tracking_number" => "A1"}, template)

    assert params == %{
             "template_id" => "7",
             "kind" => "exercise",
             "title" => "Monday night training",
             "start_time" => "19:00",
             "finish_time" => "21:30",
             "place" => "Hall",
             "coordinate" => "49.10000,-123.10000",
             "hours" => "secondary",
             "description" => "<div>Bring a radio.</div>",
             "tracking_number" => "A1"
           }
  end

  test "a template with no details fills its name and leaves what was typed" do
    template = %App.Model.Template{id: 7, title: "Truck 1", hours: "primary"}
    params = ActivityFormViewModel.template_params(%{"place" => "Yard"}, template)

    assert params == %{
             "template_id" => "7",
             "title" => "Truck 1",
             "hours" => "primary",
             "place" => "Yard"
           }
  end

  test "with a template, a date and two times; a finish before the start is the next day" do
    params = %{
      template_id: "7",
      title: "Night search",
      date: "2026-11-02",
      start_time: "22:00",
      finish_time: "02:00"
    }

    assert {:ok, form} = ActivityFormViewModel.validate(%ActivityFormViewModel{}, params)
    assert form.starts_at == ~N[2026-11-02 22:00:00]
    assert form.ends_at == ~N[2026-11-03 02:00:00]

    assert {:error, changeset} =
             ActivityFormViewModel.validate(%ActivityFormViewModel{}, %{params | date: ""})

    assert {"Enter the date.", _} = changeset.errors[:date]
    refute changeset.errors[:starts_at]
  end
end
