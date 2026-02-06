defmodule App.Operation.RefreshD4HData.UpsertQualifications do
  alias App.Adapter.D4H
  alias App.Model.Qualification

  def call(d4h, team) do
    d4h_qualifications = D4H.fetch_qualifications(d4h)

    Enum.each(d4h_qualifications, fn d4h_qualification ->
      upsert_qualification(team, d4h_qualification)
    end)

    :ok
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
