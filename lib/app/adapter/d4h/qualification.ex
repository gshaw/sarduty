defmodule App.Adapter.D4H.Qualification do
  defstruct d4h_qualification_id: nil,
            title: nil,
            expires_months_default: nil,
            organization_owned: false

  # A team's list includes its organization's qualifications, owned by the "Organisation".
  def build(record) do
    %__MODULE__{
      d4h_qualification_id: record["id"],
      title: record["title"],
      expires_months_default: record["expiresMonthsDefault"],
      organization_owned: get_in(record, ["owner", "resourceType"]) == "Organisation"
    }
  end
end
