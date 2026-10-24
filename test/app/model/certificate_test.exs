defmodule App.Model.CertificateTest do
  use ExUnit.Case, async: true

  alias App.Model.Certificate
  alias App.Model.Qualification

  @params %{"qualification_id" => "7", "starts_on" => "2026-10-18", "ends_on" => "2029-10-18"}

  defp errors(params) do
    %Certificate{}
    |> Certificate.build_changeset(Map.merge(@params, params), [7])
    |> Map.fetch!(:errors)
    |> Enum.map(fn {field, {message, _opts}} -> {field, message} end)
  end

  test "a certificate takes one of the team's qualifications, a start, and an expiry if any" do
    assert errors(%{}) == []
    assert errors(%{"ends_on" => ""}) == []
    assert errors(%{"qualification_id" => "8"}) == [qualification_id: "Select a qualification"]
    assert errors(%{"starts_on" => ""}) == [starts_on: "Enter the date on the certificate"]
    assert errors(%{"ends_on" => "2026-10-18"}) == [ends_on: "Enter an expiry after the start"]
  end

  test "the expiry fills in from D4H's length, else the member's last award" do
    three_years = %Qualification{expires_months_default: 36}
    none = %Qualification{expires_months_default: nil}
    last = %{starts_at: ~U[2023-11-12 08:00:00Z], ends_at: ~U[2025-11-11 08:00:00Z]}

    assert Certificate.default_ends_on(~D[2026-10-18], three_years, last) ==
             {~D[2029-10-18], 36}

    assert Certificate.default_ends_on(~D[2026-10-18], none, last) == {~D[2028-10-18], 24}
    assert Certificate.default_ends_on(~D[2026-10-18], none, nil) == nil
    assert Certificate.default_ends_on(~D[2026-10-18], none, %{last | ends_at: nil}) == nil
    assert Certificate.default_ends_on(nil, three_years, nil) == nil
  end

  test "the member changes it only until its award is in D4H" do
    assert Certificate.member_can_change?(%Certificate{status: :waiting})
    refute Certificate.member_can_change?(%Certificate{status: :waiting, d4h_award_id: 3})
    refute Certificate.member_can_delete?(%Certificate{status: :waiting, d4h_award_id: 3})
    refute Certificate.member_can_delete?(%Certificate{status: :accepted})
    assert Certificate.member_can_delete?(%Certificate{status: :declined})
  end
end
