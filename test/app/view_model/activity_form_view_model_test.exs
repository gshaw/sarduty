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
end
