defmodule App.Worker.ReseedSampleWorkerTest do
  # Not async: it rewrites Coast Range SAR's database, which async tests read.
  use ExUnit.Case, async: false

  alias App.Model.Member
  alias App.Worker.ReseedSampleWorker

  import Ecto.Query, only: [where: 3]

  test "seeds Coast Range SAR again, with the same ids" do
    team = App.SampleRepo.team()
    cameron = App.SampleRepo.get_by!(Member, ref_id: "132")

    assert :ok = ReseedSampleWorker.perform(%Oban.Job{args: %{}})

    assert App.SampleRepo.team().id == team.id
    assert App.SampleRepo.get_by!(Member, ref_id: "132").id == cameron.id
    members = Member |> where([m], m.team_id == ^team.id) |> App.SampleRepo.aggregate(:count)
    assert members == length(App.CoastRange.names())
  end
end
