defmodule App.Adapter.D4H.Group do
  defstruct d4h_group_id: nil,
            title: nil,
            organization_owned: false

  # A team's list includes its organization's groups, owned by the "Organisation".
  def build(record) do
    %__MODULE__{
      d4h_group_id: record["id"],
      title: record["title"],
      organization_owned: get_in(record, ["owner", "resourceType"]) == "Organisation"
    }
  end
end
