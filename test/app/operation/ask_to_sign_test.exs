defmodule App.Operation.AskToSignTest do
  # Asking a form's task leader to sign (#993): whom a team admin may ask, and when a
  # request no longer asks the task leader.
  use ExUnit.Case, async: true

  alias App.Model.Member
  alias App.Model.SignRequest
  alias App.Model.Team
  alias App.Operation.AskToSign

  @team %Team{id: 1, member_logins: true}
  @cameron %Member{id: 2, name: "Cameron Ruiz", email: "cameron@example.com"}
  @now ~U[2026-11-11 18:00:00Z]

  test "nobody's asked when the task leader signs, or no one member has the name" do
    assert AskToSign.askable(nil, @team, @now) == :none
    assert AskToSign.askable(%{signed_for: nil, leader: @cameron}, @team, @now) == :none
    assert AskToSign.askable(%{signed_for: "Ave Chen", leader: nil}, @team, @now) == :none
  end

  test "a task leader with no email cannot log in to sign it" do
    signed = %{signed_for: "Cameron Ruiz", leader: %{@cameron | email: nil}}

    assert AskToSign.askable(signed, @team, @now) ==
             {:error, "Cameron Ruiz has no email, so they cannot log in to sign it."}
  end

  test "a request still asks the one member the Task Leader's Name names" do
    request = %SignRequest{member_id: 2}

    refute AskToSign.leader_changed?(request, %{name: "cameron ruiz", members: [@cameron]})
    assert AskToSign.leader_changed?(request, %{name: "Harper Nguyen", members: [%Member{id: 3}]})
    assert AskToSign.leader_changed?(request, %{name: "Ave Chen", members: []})
    assert AskToSign.leader_changed?(request, %{name: nil, members: []})
  end
end
