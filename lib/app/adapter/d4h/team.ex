defmodule App.Adapter.D4H.Team do
  defstruct team_id: nil,
            organisation_id: nil,
            title: nil,
            coordinate: nil

  alias App.Model.Coordinate

  def build(record) do
    %__MODULE__{
      team_id: record["team_id"],
      organisation_id: record["organisation_id"],
      title: record["title"],
      coordinate: Coordinate.build(record)
    }
  end
end
