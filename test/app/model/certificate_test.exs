defmodule App.Model.CertificateTest do
  use ExUnit.Case, async: true

  alias App.Model.Certificate
  alias App.Model.Qualification

  @params %{"qualification_id" => "7", "starts_on" => "2026-10-18", "ends_on" => "2029-10-18"}

  defp errors(changeset_fun, params) do
    %Certificate{}
    |> changeset_fun.(Map.merge(@params, params), [7])
    |> Map.fetch!(:errors)
    |> Enum.map(fn {field, {message, _opts}} -> {field, message} end)
  end

  test "a member sends a start, an expiry if any, and the qualification only if they know it" do
    member = &Certificate.member_changeset/3
    assert errors(member, %{}) == []
    assert errors(member, %{"ends_on" => ""}) == []
    assert errors(member, %{"qualification_id" => ""}) == []

    assert errors(member, %{"qualification_id" => "8"}) == [
             qualification_id: "Select a qualification"
           ]

    assert errors(member, %{"starts_on" => ""}) == [
             starts_on: "Enter the date on the certificate"
           ]

    assert errors(member, %{"ends_on" => "2026-10-18"}) == [
             ends_on: "Enter an expiry after the start"
           ]

    assert errors(member, %{"note" => String.duplicate("a", 301)}) ==
             [note: "Keep the note under 300 characters"]
  end

  test "a team admin accepts a qualification once they select the box" do
    accept = &Certificate.accept_changeset/3
    assert errors(accept, %{"confirmed" => "true"}) == []
    assert errors(accept, %{}) == [confirmed: "Check the certificate, then select the box"]

    assert errors(accept, %{"confirmed" => "false"}) == [
             confirmed: "Check the certificate, then select the box"
           ]

    assert errors(accept, %{"qualification_id" => "", "confirmed" => "true"}) ==
             [qualification_id: "Select a qualification"]
  end

  test "dates that look wrong are warnings: a start after today, or not the usual length" do
    today = ~D[2026-10-24]
    usual = {~D[2029-10-18], 36}
    assert Certificate.date_warnings(~D[2026-10-18], ~D[2029-10-18], usual, today) == []
    # A certificate to the end of the month is still the usual length.
    assert Certificate.date_warnings(~D[2026-10-18], ~D[2029-10-31], usual, today) == []

    assert Certificate.date_warnings(~D[2027-10-18], ~D[2029-10-18], {~D[2030-10-18], 36}, today) ==
             [:starts_after_today, {:length, 36, 24}]

    assert Certificate.date_warnings(~D[2026-10-18], nil, usual, today) == [{:no_expiry, 36}]
    # With no usual length, only the start is checked.
    assert Certificate.date_warnings(~D[2007-06-26], ~D[2010-06-26], nil, today) == []
    assert Certificate.date_warnings(nil, nil, nil, today) == []
  end

  test "an expiry on or before today goes in as a past award" do
    assert Certificate.expired_by?(~D[2010-06-26], ~D[2026-10-24])
    assert Certificate.expired_by?(~D[2026-10-24], ~D[2026-10-24])
    refute Certificate.expired_by?(~D[2029-10-18], ~D[2026-10-24])
    refute Certificate.expired_by?(nil, ~D[2026-10-24])
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
