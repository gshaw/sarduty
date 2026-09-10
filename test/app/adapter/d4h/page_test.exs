defmodule App.Adapter.D4H.PageTest do
  use ExUnit.Case, async: true

  alias App.Adapter.D4H.Error
  alias App.Adapter.D4H.Page

  # The example response for GET /attendance in D4H's API spec (/v3/docs/swagger.json).
  @attendance_body %{
    "results" => [
      %{
        "activity" => %{"resourceType" => "Incident", "id" => 1},
        "createdAt" => "2026-09-05T21:51:35.767Z",
        "duration" => 1,
        "endsAt" => "2026-09-05T21:51:35.767Z",
        "id" => 1,
        "member" => %{"resourceType" => "Member", "id" => 1},
        "owner" => %{"resourceType" => "Team", "id" => 1},
        "startsAt" => "2026-09-05T21:51:35.767Z",
        "status" => "ABSENT",
        "resourceType" => "ActivityAttendance",
        "role" => %{"id" => 1, "resourceType" => "Role"},
        "updatedAt" => "2026-09-05T21:51:35.767Z"
      }
    ],
    "page" => 0,
    "pageSize" => 1,
    "totalSize" => 1
  }

  # What D4H returned to a team still using a legacy token.
  @unauthorized_body %{
    "detail" =>
      "Legacy tokens are not supported on this API, you must use a Personal Access Token.",
    "detailObj" => %{},
    "status" => 401,
    "title" => "Legacy Tokens Not Supported"
  }

  defp page(result_count, total_size) do
    %Page{results: List.duplicate(%{}, result_count), total_size: total_size}
  end

  test "reads the rows and D4H's total from a list response" do
    assert {:ok, page} = Page.build(@attendance_body)
    assert page.total_size == 1
    assert [%{"id" => 1}] = page.results
  end

  test "an error body is not a page" do
    assert Page.build(@unauthorized_body) == :error
  end

  test "stops once the fetched rows cover D4H's total" do
    last_page = page(500, 2500)
    assert Page.next(last_page, 2500) == :done
  end

  test "asks for another page while rows are still due" do
    first_page = page(1000, 2500)
    assert Page.next(first_page, 1000) == :next
  end

  test "an empty page before D4H's total is short" do
    empty_page = page(0, 2500)
    assert Page.next(empty_page, 1000) == :short
  end

  test "a team with no rows is done after one empty page" do
    empty_page = page(0, 0)
    assert Page.next(empty_page, 0) == :done
  end

  test "an error response names the status and D4H's reason" do
    error = Error.exception(%Req.Response{status: 401, body: @unauthorized_body})

    assert error.status == 401
    assert error.message =~ "D4H API error (401)"
    assert error.message =~ "Legacy Tokens Not Supported"
  end
end
