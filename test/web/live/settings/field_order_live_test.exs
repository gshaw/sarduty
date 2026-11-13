defmodule Web.Settings.FieldOrderLiveTest do
  use Web.ConnCase, async: true

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.RecordsStub
  alias App.Repo

  # Change order (#1056 step 4), on a SAR Duty Records team through App.RecordsStub.
  # Never D4H.

  setup %{conn: conn} do
    %{user: user, team: team} = records_team_with_user_fixture(%{d4h_access_key: "sdr_key"})
    organization_fixture([team], %{short_name: "WESARA"})

    own = fn title, id, ordering ->
      custom_field_fixture(team, %{
        title: title,
        d4h_custom_field_id: id,
        ordering: ordering,
        owner_type: "Team",
        owner_id: team.d4h_team_id
      })
    end

    fields = [
      own.("People helped", 91, 0),
      own.("Requesting agency", 92, 1),
      own.("Team notes", 93, 2)
    ]

    custom_field_fixture(team, %{title: "Agency", owner_type: "Organisation", ordering: 0})

    %{conn: log_in_user(conn, user), team: team, fields: fields}
  end

  test "the Fields tab offers Change order for a kind with 2 or more own fields",
       %{conn: conn, team: team} do
    custom_field_fixture(team, %{target: "member", owner_type: "Team", owner_id: team.d4h_team_id})

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/fields?kind=incident")

    assert has_element?(
             lv,
             "#field-order[href='/teams/#{team.subdomain}/settings/fields/order?kind=incident']",
             "Change order"
           )

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/fields?kind=member")
    refute has_element?(lv, "#field-order")
  end

  test "lists the team's own fields with a handle and Move up and Move down",
       %{conn: conn, team: team, fields: [first, _, last]} do
    {:ok, lv, html} = live(conn, ~p"/teams/#{team}/settings/fields/order?kind=incident")

    assert html =~ "The order of your team&#39;s incident fields on an incident."
    assert html =~ "WESARA&#39;s fields keep their own order."
    assert has_element?(lv, "#field-order-list-row-#{first.id}", "People helped")
    refute has_element?(lv, "#field-order-list", "Agency")
    assert has_element?(lv, "#field-order-list-row-#{first.id} [aria-label='Move People helped']")
    assert has_element?(lv, "#field-order-list-row-#{first.id} [data-move=up][disabled]")
    refute has_element?(lv, "#field-order-list-row-#{first.id} [data-move=down][disabled]")
    assert has_element?(lv, "#field-order-list-row-#{last.id} [data-move=down][disabled]")
  end

  test "saves a new order: a row for each field that moved",
       %{conn: conn, team: team, fields: [a, b, c]} do
    RecordsStub.stub(fn "PATCH", "/custom-fields/" <> id, body ->
      {200,
       %{
         "id" => String.to_integer(id),
         "targetResourceType" => "Incident",
         "title" => "Field",
         "type" => "TEXT",
         "ordering" => body["ordering"],
         "owner" => %{"resourceType" => "Team", "id" => team.d4h_team_id}
       }}
    end)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/fields/order?kind=incident")

    lv
    |> element("#field-order-list")
    |> render_hook("reorder", %{"keys" => Enum.map([b, a, c], &to_string(&1.id))})

    assert has_element?(lv, "#field-order-list-row-#{b.id} [data-move=up][disabled]")

    {:ok, _lv, html} =
      lv
      |> form("#order-form")
      |> render_submit()
      |> follow_redirect(conn, ~p"/teams/#{team}/settings/fields?kind=incident")

    assert html =~ "Saved the order of your incident fields."
    assert_received {:records, "PATCH", "/custom-fields/92", %{"ordering" => 0}}
    assert_received {:records, "PATCH", "/custom-fields/91", %{"ordering" => 1}}
    refute_received {:records, "PATCH", "/custom-fields/93", _}
  end

  test "a key that cannot change fields has no Change order", %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: "key"}})
    team = team |> Ecto.Changeset.change(d4h_permissions: %{}) |> Repo.update!()

    for {title, ordering} <- [{"One", 0}, {"Two", 1}],
        do:
          custom_field_fixture(team, %{
            title: title,
            ordering: ordering,
            owner_type: "Team",
            owner_id: team.d4h_team_id
          })

    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/teams/#{team}/settings/fields?kind=incident")
    refute has_element?(lv, "#field-order")

    assert_raise Web.Status.NotFound, fn ->
      live(conn, ~p"/teams/#{team}/settings/fields/order?kind=incident")
    end
  end
end
