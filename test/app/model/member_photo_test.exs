defmodule App.Model.MemberPhotoTest do
  use App.DataCase, async: true

  import App.DataFixtures

  alias App.Accounts.User
  alias App.Model.MemberPhoto

  # A photo a member added of themselves (#1029).
  @now ~U[2026-11-12 20:00:00.000000Z]
  @user %User{id: 4}

  describe "decline_changeset/5" do
    defp errors(reason, message) do
      %MemberPhoto{}
      |> MemberPhoto.decline_changeset(reason, message, @user, @now)
      |> Map.fetch!(:errors)
      |> Enum.map(fn {field, {text, _opts}} -> {field, text} end)
    end

    test "takes one reason from the list, and a message of up to 300 characters" do
      for {key, _text} <- MemberPhoto.reasons() do
        assert errors(Atom.to_string(key), nil) == []
      end

      assert errors("dark", String.duplicate("a", 300)) == []

      assert errors("dark", String.duplicate("a", 301)) ==
               [decline_message: "Keep it under 300 characters."]
    end

    test "no reason, or one that is not on the list, asks for one" do
      for reason <- [nil, "", "blurry"] do
        assert errors(reason, "A message alone is not a reason.") ==
                 [decline_reason: "Select why not."]
      end
    end

    test "says who declined it and when" do
      changeset = MemberPhoto.decline_changeset(%MemberPhoto{}, "hat", " Hat off. ", @user, @now)

      assert %{
               status: :declined,
               decline_reason: :hat,
               decline_message: "Hat off.",
               decided_by_user_id: 4,
               decided_at: @now
             } = Ecto.Changeset.apply_changes(changeset)
    end
  end

  test "the reasons read as the check page lists them" do
    assert Keyword.values(MemberPhoto.reasons()) == [
             "Sunglasses",
             "Hat or helmet",
             "Too dark",
             "Someone else in it",
             "Busy background",
             "Not a photo of you",
             "Something else"
           ]

    assert MemberPhoto.reason_text(:not_you) == "Not a photo of you"
  end

  describe "unanswered?/2" do
    @declined %MemberPhoto{status: :declined, decided_at: @now}

    test "a decline waits on the member until someone sets their photo" do
      assert MemberPhoto.unanswered?(@declined, nil)
      # A photo set before the decline is the one the declined photo was to replace.
      assert MemberPhoto.unanswered?(@declined, DateTime.add(@now, -1, :day))
      # A team admin's own Add a photo since answers it.
      refute MemberPhoto.unanswered?(@declined, DateTime.add(@now, 1, :hour))
    end

    test "a waiting or accepted photo asks nothing of the member" do
      for status <- [:waiting, :accepted] do
        refute MemberPhoto.unanswered?(%MemberPhoto{status: status}, nil)
      end
    end
  end

  describe "the member's photos" do
    setup do
      team = team_fixture(%{photos_enabled: true})
      %{team: team, cam: member_fixture(team, %{name: "Cameron Ruiz"})}
    end

    test "only the last one they added can ask them for another", %{cam: cam} do
      assert MemberPhoto.declined_for_member(cam) == nil

      declined =
        member_photo_fixture(cam, %{status: :declined, decline_reason: :dark, decided_at: @now})

      assert MemberPhoto.declined_for_member(cam).id == declined.id
      assert MemberPhoto.waiting_for_member(cam) == nil

      waiting = member_photo_fixture(cam)
      assert MemberPhoto.declined_for_member(cam) == nil
      assert MemberPhoto.waiting_for_member(cam).id == waiting.id
    end

    test "a photo a team admin set since the decline answers it", %{cam: cam} do
      member_photo_fixture(cam, %{status: :declined, decline_reason: :dark, decided_at: @now})
      cam = %{cam | photo_changed_at: ~U[2026-11-13 08:00:00Z]}

      assert MemberPhoto.declined_for_member(cam) == nil
    end

    test "waiting photos are the team's counted, current members', oldest first", %{
      team: team,
      cam: cam
    } do
      newer = member_photo_fixture(cam, %{inserted_at: ~U[2026-11-12 20:00:00.000000Z]})
      sam = member_fixture(team, %{name: "Sam Rivera"})
      older = member_photo_fixture(sam, %{inserted_at: ~U[2026-11-10 20:00:00.000000Z]})

      # Not counted: retired, not a person, another team's, and one already decided.
      retired = member_fixture(team, %{left_at: ~U[2020-01-01 00:00:00Z]})
      member_photo_fixture(retired)
      member_photo_fixture(member_fixture(team, %{not_a_person: true}))
      member_photo_fixture(member_fixture(team_fixture()))
      member_photo_fixture(sam, %{status: :accepted})

      assert [first, second] = MemberPhoto.get_waiting(team, @now)
      assert {first.id, second.id} == {older.id, newer.id}
      assert first.member.name == "Sam Rivera"
      assert MemberPhoto.count_waiting(team, @now) == 2
    end
  end
end
