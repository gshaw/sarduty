defmodule App.Adapter.D4H.Group do
  defstruct d4h_group_id: nil,
            title: nil

  def build(record) do
    %__MODULE__{
      d4h_group_id: record["id"],
      title: record["title"]
    }
  end
end
