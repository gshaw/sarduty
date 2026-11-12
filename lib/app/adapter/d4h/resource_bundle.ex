defmodule App.Adapter.D4H.ResourceBundle do
  alias App.Adapter.D4H.CustomField

  # One of D4H's resource bundles (#872): a named group of one kind's custom fields, such
  # as BCSARA's "KMS Data" on incidents. A team's list holds its organisation's too. Only
  # bundles of custom fields on the targets SAR Duty copies are built; the rest, such as
  # health and safety reports', come back nil.
  defstruct d4h_bundle_id: nil,
            title: nil,
            target: nil,
            ordering: 0,
            owner_type: nil,
            owner_id: nil

  def build(%{"target" => %{"resourceType" => "CustomField"} = target} = record) do
    case CustomField.target(target["subResourceType"]) do
      nil -> nil
      kind -> build(record, kind)
    end
  end

  def build(_record), do: nil

  defp build(record, target) do
    owner = if is_map(record["owner"]), do: record["owner"], else: %{}

    %__MODULE__{
      d4h_bundle_id: record["id"],
      title: record["title"],
      target: target,
      ordering: record["ordering"] || 0,
      owner_type: owner["resourceType"],
      owner_id: owner["id"]
    }
  end
end
