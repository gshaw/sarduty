defmodule App.Adapter.D4H.Tag do
  defstruct d4h_tag_id: nil,
            title: nil,
            owner_type: nil,
            owner_id: nil

  # `owner` is the team or organisation that made the tag. A missing one stays nil.
  def build(record) do
    owner = if is_map(record["owner"]), do: record["owner"], else: %{}

    %__MODULE__{
      d4h_tag_id: record["id"],
      title: record["title"],
      owner_type: owner["resourceType"],
      owner_id: owner["id"]
    }
  end
end
