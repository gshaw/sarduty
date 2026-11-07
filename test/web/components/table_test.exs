defmodule Web.Components.TableTest do
  use ExUnit.Case, async: true

  import Web.Components.Table, only: [sort_header: 2]

  @both_ways [{"↓", "date-"}, {"↑", "date"}]

  describe "sort_header/2 for a column that sorts both ways" do
    test "links to its first sort when the table is sorted by another column" do
      assert sort_header(@both_ways, "name") == %{
               suffix: "⇅",
               current?: false,
               link?: true,
               next_sort: "date-",
               aria_sort: nil
             }
    end

    test "links to its first sort when the table has no sort" do
      assert %{link?: true, next_sort: "date-", aria_sort: nil} = sort_header(@both_ways, nil)
    end

    test "sorted descending, links to ascending" do
      assert sort_header(@both_ways, "date-") == %{
               suffix: "↓",
               current?: true,
               link?: true,
               next_sort: "date",
               aria_sort: "descending"
             }
    end

    test "sorted ascending, links to descending" do
      assert sort_header(@both_ways, "date") == %{
               suffix: "↑",
               current?: true,
               link?: true,
               next_sort: "date-",
               aria_sort: "ascending"
             }
    end
  end

  describe "sort_header/2 for a column that sorts one way" do
    test "shows its own arrow, faded, and links to its sort" do
      assert sort_header([{"↑", "name"}], "role") == %{
               suffix: "↑",
               current?: false,
               link?: true,
               next_sort: "name",
               aria_sort: nil
             }
    end

    test "is not a link when the table is sorted by it" do
      assert sort_header([{"↓", "total"}], "total") == %{
               suffix: "↓",
               current?: true,
               link?: false,
               next_sort: nil,
               aria_sort: "descending"
             }
    end
  end

  describe "fit" do
    import Phoenix.Component
    import Phoenix.LiveViewTest

    test "the header carries the longest values unseen, and the column's cells fit" do
      assigns = %{rows: [%{name: "Avery Chen", reply: "Signed up"}]}

      html =
        rendered_to_string(~H"""
        <Web.Components.Table.table id="t" rows={@rows}>
          <:col :let={row} label="Member">{row.name}</:col>
          <:col :let={row} label="Reply" fit={["Signed up", "Can't make it"]}>{row.reply}</:col>
        </Web.Components.Table.table>
        """)

      doc = LazyHTML.from_fragment(html)
      assert doc |> LazyHTML.query("th.col-fit .col-fit-sizer[aria-hidden]") |> Enum.count() == 2
      assert doc |> LazyHTML.query("td.col-fit") |> LazyHTML.text() =~ "Signed up"
      assert doc |> LazyHTML.query("th:not(.col-fit)") |> LazyHTML.text() =~ "Member"
    end
  end
end
