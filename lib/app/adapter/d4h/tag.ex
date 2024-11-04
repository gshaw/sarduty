defmodule App.Adapter.D4H.Tag do
  defstruct d4h_tag_id: nil,
            title: nil

  def build(record) do
    %__MODULE__{
      d4h_tag_id: record["id"],
      title: record["title"]
    }
  end
end
