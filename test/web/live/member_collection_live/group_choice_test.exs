defmodule Web.MemberCollectionLive.GroupChoiceTest do
  # Add to group and Remove from group under the Members table: the hints, the button,
  # and the confirm (round 5's G). cspell:ignore Okafor
  use ExUnit.Case, async: true

  alias App.Model.Member
  alias Web.MemberCollectionLive.GroupChoice

  @avery %Member{id: 1, name: "Avery Chen"}
  @cameron %Member{id: 2, name: "Cameron Ruiz"}
  @riley %Member{id: 3, name: "Riley Okafor"}
  @three [@avery, @cameron, @riley]

  # Avery is in Rope team.
  @rope %{title: "Rope team", retiring?: false, member_ids: MapSet.new([1])}
  @retiring %{title: "Retiring", retiring?: true, member_ids: MapSet.new([1])}

  defp many(n), do: for(id <- 1..n, do: %Member{id: id, name: "Member #{id}"})
  defp group(ids), do: %{@rope | member_ids: MapSet.new(ids)}

  describe "hint/3" do
    test "with nothing checked, or no group yet, the sentence without counts or the group" do
      assert GroupChoice.hint(:add, [], @rope) ==
               "Adds the checked to the group you select. Anyone in it already is skipped."

      assert GroupChoice.hint(:remove, @three, nil) ==
               "Takes the 3 checked out of the group you select. Anyone not in it is skipped."
    end

    test "counts who it reaches and names who it skips" do
      assert GroupChoice.hint(:add, @three, @rope) ==
               "Adds 2 of the 3 checked to Rope team. Avery Chen is in it already."

      assert GroupChoice.hint(:remove, @three, @rope) ==
               "Takes 1 of the 3 checked out of Rope team. Cameron Ruiz and Riley Okafor aren't in it."

      assert GroupChoice.hint(:remove, [@avery], @rope) == "Takes the 1 checked out of Rope team."

      assert GroupChoice.hint(:add, [@cameron, @riley], @rope) ==
               "Adds all 2 checked to Rope team."
    end

    test "counts who it skips past 3" do
      assert GroupChoice.hint(:add, many(16), group(1..5)) ==
               "Adds 11 of the 16 checked to Rope team. 5 are in it already."
    end

    test "says why when it reaches nobody" do
      assert GroupChoice.hint(:add, [@avery], @rope) ==
               "Everyone checked is in Rope team already."

      assert GroupChoice.hint(:remove, [@cameron], @rope) == "Nobody checked is in Rope team."
    end

    test "Retiring says what they lose or get back" do
      assert GroupChoice.hint(:add, [@cameron], @retiring) ==
               "Marks the 1 checked as retiring. They can't log in to SAR Duty from now on."

      assert GroupChoice.hint(:add, [@avery, @cameron], @retiring) ==
               "Marks 1 of the 2 checked as retiring. They can't log in to SAR Duty from now on. Avery Chen is retiring already."

      assert GroupChoice.hint(:remove, [@avery], @retiring) ==
               "Marks the 1 checked as not retiring. They can log in to SAR Duty again."

      assert GroupChoice.hint(:remove, [@cameron], @retiring) == "Nobody checked is retiring."
    end
  end

  test "waiting/3 says why the button is greyed" do
    assert GroupChoice.waiting(:add, @three, nil) == "Select a group."

    assert GroupChoice.waiting(:add, [@avery], @rope) ==
             "Everyone checked is in Rope team already."

    assert GroupChoice.waiting(:add, @three, @rope) == nil
  end

  test "button_text/3 counts and never names the group" do
    assert GroupChoice.button_text(:add, 2, @rope) == "Add 2 to group"
    assert GroupChoice.button_text(:remove, 1, @rope) == "Remove 1 from group"
    assert GroupChoice.button_text(:add, 0, @rope) == "Add to group"
    assert GroupChoice.button_text(:add, 3, @retiring) == "Mark 3 as retiring"
    assert GroupChoice.button_text(:remove, 1, @retiring) == "Mark 1 as not retiring"
  end

  describe "confirm/4" do
    test "adding to a group kept by hand doesn't ask" do
      assert GroupChoice.confirm(:add, [@cameron], @rope, "D4H") == %{}
      assert GroupChoice.confirm(:remove, [], @rope, "D4H") == %{}
    end

    test "Remove names up to 3 of who it removes, then counts, and from 10 a box" do
      assert GroupChoice.confirm(:remove, [@riley, @avery], @rope, "D4H") ==
               %{"data-confirm" => "Remove Avery Chen and Riley Okafor from Rope team?"}

      assert GroupChoice.confirm(:remove, many(6), @rope, "D4H") ==
               %{"data-confirm" => "Remove 6 members from Rope team?"}

      assert GroupChoice.confirm(:remove, many(12), @rope, "D4H") == %{
               "data-confirm" => "Remove 12 members from Rope team?",
               "data-confirm-check" => "I understand 12 members leave Rope team."
             }
    end

    test "Retiring asks both ways" do
      assert GroupChoice.confirm(:add, [@cameron], @retiring, "D4H") == %{
               "data-confirm" =>
                 "Mark Cameron Ruiz as retiring? They can't log in to SAR Duty from now on. Take away their D4H access too."
             }

      assert GroupChoice.confirm(:add, many(12), @retiring, "D4H")["data-confirm-check"] ==
               "I understand 12 members can't log in."

      assert GroupChoice.confirm(:remove, [@avery], @retiring, "D4H") == %{
               "data-confirm" =>
                 "Mark Avery Chen as not retiring? They can log in to SAR Duty again, and SAR Duty counts them again."
             }
    end
  end
end
