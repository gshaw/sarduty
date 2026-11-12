defmodule App.Operation.SignFormTest do
  # Who signs a form and for whom (#993): the task leader in their own name, anyone else
  # in theirs, for the task leader.
  use ExUnit.Case, async: true

  alias App.Model.Member
  alias App.Operation.SignForm

  @day ~D[2026-11-11]
  @alex %Member{id: 1, name: "Alex Chen", email: "alex@example.com", phone: "604-555-0112"}
  @cameron %Member{id: 2, name: "Cameron Ruiz", email: "cameron@example.com"}

  test "the task leader signs in their own name, for no one" do
    signed = SignForm.signing(@cameron, %{name: "cameron ruiz", members: [@cameron]}, @day)

    assert %{signed_by: "Cameron Ruiz", signed_for: nil, signed_on: @day, problem: nil} = signed
    refute SignForm.tells_leader?(signed)
  end

  test "anyone else signs in their own name, for the task leader, who hears about it" do
    signed = SignForm.signing(@alex, %{name: "cameron  ruiz", members: [@cameron]}, @day)

    assert %{signed_by: "Alex Chen", signed_for: "Cameron Ruiz", leader: @cameron} = signed
    assert %{email: "alex@example.com", phone: "604-555-0112"} = signed
    assert SignForm.tells_leader?(signed)

    assert %{"signer.signature" => {:signature, "Alex Chen", "Cameron Ruiz"}} =
             SignForm.values(signed)

    no_email = SignForm.signing(@alex, %{name: "x", members: [%{@cameron | email: " "}]}, @day)
    refute SignForm.tells_leader?(no_email)
  end

  test "with no member by that name, or two, it's for the name as written and nobody hears" do
    for {members, problem} <- [
          {[], "No member is named Ave Chen"},
          {[@cameron, %{@cameron | id: 3}], "2 members are named Ave Chen"}
        ] do
      signed = SignForm.signing(@alex, %{name: "Ave Chen", members: members}, @day)

      assert %{signed_for: "Ave Chen", leader: nil, problem: ^problem} = signed
      refute SignForm.tells_leader?(signed)
    end
  end

  test "names the same person whatever their case and spaces" do
    assert Member.same_name("  Cameron   RUIZ ") == Member.same_name("cameron ruiz")
  end
end
