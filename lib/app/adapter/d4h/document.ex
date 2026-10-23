defmodule App.Adapter.D4H.Document do
  defstruct d4h_document_id: nil,
            title: nil,
            file_extension: nil,
            file_size: nil,
            file_type: nil,
            available_sizes: [],
            d4h_target_id: nil

  def build(record) do
    %__MODULE__{
      d4h_document_id: record["id"],
      d4h_target_id: get_in(record, ["targetResource", "id"]),
      file_extension: record["fileExt"],
      file_size: record["fileSize"],
      file_type: record["fileType"],
      available_sizes: record["availableSizes"]
    }
  end
end
