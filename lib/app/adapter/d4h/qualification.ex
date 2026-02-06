defmodule App.Adapter.D4H.Qualification do
  defstruct d4h_qualification_id: nil,
            title: nil

  def build(record) do
    %__MODULE__{
      d4h_qualification_id: record["id"],
      title: record["title"]
    }
  end
end
