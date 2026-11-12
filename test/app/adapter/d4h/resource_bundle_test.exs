defmodule App.Adapter.D4H.ResourceBundleTest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H.ResourceBundle

  # As South Fraser's list showed BCSARA's, 2026-11-12.
  @kms %{
    "id" => 43,
    "title" => "KMS Data",
    "ordering" => 0,
    "owner" => %{"id" => 7, "resourceType" => "Organisation"},
    "target" => %{"resourceType" => "CustomField", "subResourceType" => "Incident"},
    "createdAt" => "2020-03-01T22:25:15.000Z"
  }

  test "builds a bundle of incident fields" do
    assert ResourceBundle.build(@kms) == %ResourceBundle{
             d4h_bundle_id: 43,
             title: "KMS Data",
             target: "incident",
             ordering: 0,
             owner_type: "Organisation",
             owner_id: 7
           }
  end

  test "a bundle of fields SAR Duty doesn't copy, or of something else, builds nothing" do
    reports = put_in(@kms, ["target", "subResourceType"], "HealthSafetyReport")
    groups = put_in(@kms, ["target", "resourceType"], "MemberGroup")

    assert ResourceBundle.build(reports) == nil
    assert ResourceBundle.build(groups) == nil
    assert @kms |> Map.delete("target") |> ResourceBundle.build() == nil
  end
end
