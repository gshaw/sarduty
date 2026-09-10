defmodule App.Operation.RefreshD4HData.UpsertQualifications do
  alias App.Adapter.D4H
  alias App.Model.Qualification
  alias App.Operation.RefreshD4HData.Progress

  @chunk_size 100

  def call(d4h, team, progress) do
    d4h_qualifications = D4H.fetch_qualifications(d4h)
    total_count = Enum.count(d4h_qualifications)

    progress = Progress.update_stage(progress, "Qualifications", total_count)

    chunks = Enum.chunk_every(d4h_qualifications, @chunk_size)

    progress =
      Enum.reduce(chunks, progress, fn chunk, progress_acc ->
        Enum.each(chunk, &upsert_qualification(team, &1))
        Progress.add_page(progress_acc, Enum.count(chunk))
      end)

    {total_count, progress}
  end

  defp upsert_qualification(team, d4h_qualification) do
    params = %{
      team_id: team.id,
      d4h_qualification_id: d4h_qualification.d4h_qualification_id,
      title: d4h_qualification.title
    }

    qualification =
      Qualification.get_by(
        team_id: team.id,
        d4h_qualification_id: d4h_qualification.d4h_qualification_id
      )

    if qualification do
      Qualification.update!(qualification, params)
    else
      Qualification.insert!(params)
    end
  end
end
