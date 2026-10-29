defmodule Web.ActivityTagsLiveTest do
  use Web.ConnCase

  import App.DataFixtures
  import Phoenix.LiveViewTest

  alias App.Model.Activity
  alias App.Model.ChangeSet
  alias App.Repo

  setup %{conn: conn} do
    %{user: user, team: team} = user_with_team_fixture(%{team: %{d4h_access_key: "team-key"}})
    activity = activity_fixture(team, %{tags: ["Primary Hours", "Flat Water"]})

    tags = %{
      primary: tag_fixture(team, "Primary Hours"),
      secondary: tag_fixture(team, "Secondary Hours"),
      water: tag_fixture(team, "Flat Water"),
      rope: tag_fixture(team, "Rope")
    }

    %{conn: log_in_user(conn, user), team: team, activity: activity, tags: tags}
  end

  # D4H answers with the tags `d4h_tags` holds now, and reports each write to the test.
  defp stub_d4h(activity, d4h_tags) do
    test_pid = self()
    path = "/exercises/#{activity.d4h_activity_id}"

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case {conn.method, String.ends_with?(conn.request_path, path)} do
        {"GET", true} ->
          Req.Test.json(conn, %{"id" => activity.d4h_activity_id, "tags" => tags(d4h_tags)})

        {"POST", _activity?} ->
          send(test_pid, {:d4h_write, conn.request_path, Jason.decode!(body)})
          Req.Test.json(conn, %{"id" => activity.d4h_activity_id})
      end
    end)
  end

  defp tags(d4h_tags),
    do: for(id <- Agent.get(d4h_tags, & &1), do: %{"resourceType" => "Tag", "id" => id})

  test "the hours and other tags are changed in D4H", ctx do
    %{primary: primary, secondary: secondary, water: water, rope: rope} = ctx.tags
    {:ok, d4h_tags} = Agent.start_link(fn -> [primary.d4h_tag_id, water.d4h_tag_id] end)
    stub_d4h(ctx.activity, d4h_tags)

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}/tags")

    assert has_element?(lv, "#activity-hours option[selected][value=primary]")
    assert has_element?(lv, "#activity-tags #tag-#{water.id}")
    refute has_element?(lv, "#activity-tags #tag-#{primary.id}")

    lv |> form("#activity-tags-form", %{hours: "secondary"}) |> render_change()
    lv |> element("#tag-remove-#{water.id}") |> render_click()
    lv |> form("#tag-search-form", %{tag_q: "rope"}) |> render_change()
    lv |> element("#tag-add-#{rope.id}") |> render_click()
    lv |> form("#activity-tags-form") |> render_submit()

    assert_received {:d4h_write, tags_path, %{"tagIds" => tag_ids}}
    assert String.ends_with?(tags_path, "/tags")
    assert Enum.sort(tag_ids) == Enum.sort([secondary.d4h_tag_id, rope.d4h_tag_id])
    assert Repo.get!(Activity, ctx.activity.id).tags == ["Rope", "Secondary Hours"]
    assert %ChangeSet{source: :tags} = Repo.get_by!(ChangeSet, activity_id: ctx.activity.id)
    assert_redirect(lv, ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}")
  end

  test "tags changed in D4H since the page opened are not overwritten", ctx do
    %{primary: primary, water: water} = ctx.tags
    {:ok, d4h_tags} = Agent.start_link(fn -> [primary.d4h_tag_id] end)
    stub_d4h(ctx.activity, d4h_tags)

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}/tags")
    Agent.update(d4h_tags, &[water.d4h_tag_id | &1])
    lv |> form("#activity-tags-form", %{hours: "none"}) |> render_submit()

    refute_received {:d4h_write, _path, _body}
    assert render(lv) =~ "The tags changed since the page opened."
  end

  test "Other is offered once the team names an other tag", ctx do
    {:ok, d4h_tags} = Agent.start_link(fn -> [ctx.tags.primary.d4h_tag_id] end)
    stub_d4h(ctx.activity, d4h_tags)
    path = ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}/tags"

    {:ok, lv, _html} = live(ctx.conn, path)
    refute has_element?(lv, "#activity-hours option[value=other]")

    social = tag_fixture(ctx.team, "Social")
    ctx.team |> Ecto.Changeset.change(other_hours_tag: "Social") |> Repo.update!()

    {:ok, lv, _html} = live(ctx.conn, path)
    lv |> form("#activity-tags-form", %{hours: "other"}) |> render_submit()

    assert_received {:d4h_write, _path, %{"tagIds" => [id]}}
    assert id == social.d4h_tag_id
  end

  test "the activity page links to its tags", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{ctx.activity.id}")
    assert has_element?(lv, "#activity-change-tags")
  end

  test "a published D4H activity says so in place of the form (#358)", ctx do
    activity = ctx.activity

    Req.Test.stub(App.Adapter.D4H, fn conn ->
      Req.Test.json(conn, %{"id" => activity.d4h_activity_id, "tags" => [], "published" => true})
    end)

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{activity.id}/tags")

    assert has_element?(lv, "#tags-published", "This activity is published")
    assert has_element?(lv, "#tags-published a", "Open in D4H")
    refute has_element?(lv, "#activity-tags-form")
    assert Repo.get!(Activity, activity.id).is_published

    {:ok, lv, _html} = live(ctx.conn, ~p"/teams/#{ctx.team}/activities/#{activity.id}")

    assert has_element?(
             lv,
             "#activity-tags-locked",
             "Published, so unpublish it to change its tags."
           )

    refute has_element?(lv, "#activity-change-tags")
    assert has_element?(lv, "#activity-apply-template")
    assert has_element?(lv, "#activity-equipment-add")
  end
end
