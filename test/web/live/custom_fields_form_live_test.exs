defmodule Web.CustomFieldsFormLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.ChangeSet
  alias App.RecordsStub
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: "d4h_key"}})
    %{conn: log_in_user(conn, user), team: team}
  end

  defp stub, do: RecordsStub.stub(&reply/3)

  defp reply(_method, "/members/" <> id, _body),
    do: {200, id |> String.to_integer() |> RecordsStub.member_json()}

  defp reply(_method, "/equipment/" <> id, _body), do: {200, %{"id" => String.to_integer(id)}}
  defp reply(_method, _path, _body), do: {200, RecordsStub.activity_json(88)}

  # D4H's writes, in the order they were made.
  defp writes do
    receive do
      {:records, method, path, body} -> [{method, path, body} | writes()]
    after
      0 -> []
    end
  end

  defp cause_field(team) do
    custom_field_fixture(team, %{
      d4h_custom_field_id: 420,
      title: "Primary Cause",
      field_type: "single_choice",
      required: true,
      options: [
        %{"id" => 1, "label" => "Lost", "ordering" => 0, "archived" => false},
        %{"id" => 2, "label" => "Injured", "ordering" => 1, "archived" => false},
        %{"id" => 3, "label" => "Old", "ordering" => 2, "archived" => true}
      ]
    })
  end

  test "an incident's fields are inputs, and saving sends only the changed ones",
       %{conn: conn, team: team} do
    stub()
    cause_field(team)

    custom_field_fixture(team, %{
      d4h_custom_field_id: 454,
      title: "Agency File #",
      hint: "The file # of the requesting agency",
      required: true
    })

    activity =
      activity_fixture(team, %{
        title: "Missing hiker",
        activity_kind: "incident",
        d4h_activity_id: 88,
        custom_values: %{"420" => [1]}
      })

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}/fields/edit")

    assert has_element?(lv, "h1", "Change fields for Missing hiker")
    assert has_element?(lv, "#custom-fields-cancel[href$='/activities/#{activity.id}/fields']")
    assert has_element?(lv, ~s(#custom-field-420 option[selected][value="1"]), "Lost")
    refute has_element?(lv, ~s(#custom-field-420 option[value="3"]))
    # A draft incident: the filled one is tagged, the empty one Missing, and saving
    # still works.
    assert has_element?(lv, "#custom-fields-missing-count", "1 of 2 needed to publish is empty.")
    assert has_element?(lv, ".field-missing label[for=custom-field-454]", "Missing")
    assert has_element?(lv, "label[for=custom-field-420] .badge", "Needed to publish")
    refute has_element?(lv, ".field-error")

    lv |> form("#custom-fields-form", fields: %{"454" => "PROS 2026-1"}) |> render_change()
    refute has_element?(lv, ".field-missing")
    refute has_element?(lv, "#custom-fields-missing-count")

    {:ok, _lv, html} =
      lv
      |> form("#custom-fields-form", fields: %{"420" => "2", "454" => "PROS 2026-1"})
      |> render_submit()
      |> follow_redirect(conn, ~p"/teams/#{team}/activities/#{activity.id}/fields")

    assert html =~ "Fields saved."
    assert [{"PATCH", "/incidents/88", body} | _rest] = writes()

    assert body == %{
             "customFieldValues" => [
               %{"id" => 420, "value" => [2]},
               %{"id" => 454, "value" => "PROS 2026-1"}
             ]
           }

    assert Repo.reload(activity).custom_values == %{"420" => [2], "454" => "PROS 2026-1"}
  end

  test "a published activity is locked", %{conn: conn, team: team} do
    cause_field(team)
    activity = activity_fixture(team, %{activity_kind: "incident", is_published: true})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/activities/#{activity.id}/fields/edit")

    assert has_element?(lv, "#custom-fields-locked")
    assert has_element?(lv, "#custom-fields-form fieldset[disabled]")
    refute has_element?(lv, "#custom-fields-form button")
    # Published, so nothing is flagged Missing.
    refute has_element?(lv, ".field-missing")
  end

  test "a member's copied fields go to D4H, and the copy takes them",
       %{conn: conn, team: team} do
    stub()

    custom_field_fixture(team, %{
      d4h_custom_field_id: 630,
      target: "member",
      title: "Radio Call Sign",
      copy_values: true
    })

    custom_field_fixture(team, %{d4h_custom_field_id: 631, target: "member", title: "Not copied"})
    member = member_fixture(team, %{custom_values: %{"630" => "SF 12"}})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/members/#{member.id}/fields/edit")
    refute has_element?(lv, "#custom-field-631")
    refute render(lv) =~ "Needed to publish."

    lv
    |> form("#custom-fields-form", fields: %{"630" => "SF 14"})
    |> render_submit()

    path = "/members/#{member.d4h_member_id}"
    assert [{"PATCH", ^path, body} | _rest] = writes()
    assert body == %{"customFieldValues" => [%{"id" => 630, "value" => "SF 14"}]}
    assert Repo.reload(member).custom_values == %{"630" => "SF 14"}

    [row] =
      ChangeSet |> Repo.all(team_id: team.id) |> Repo.preload(:rows) |> Enum.flat_map(& &1.rows)

    assert %{action: :update_member, member_id: member_id, status: :applied} = row
    assert member_id == member.id
  end

  test "an item's fields go to D4H", %{conn: conn, team: team} do
    stub()

    custom_field_fixture(team, %{
      d4h_custom_field_id: 603,
      target: "equipment",
      title: "Equipment Description"
    })

    item = equipment_item_fixture(team)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/equipment/#{item.id}/fields/edit")

    lv
    |> form("#custom-fields-form", fields: %{"603" => "Orange dry bag"})
    |> render_submit()

    path = "/equipment/#{item.d4h_equipment_id}"
    assert [{"PATCH", ^path, body} | _rest] = writes()
    assert body == %{"customFieldValues" => [%{"id" => 603, "value" => "Orange dry bag"}]}
    assert Repo.reload(item).custom_values == %{"603" => "Orange dry bag"}
  end
end
