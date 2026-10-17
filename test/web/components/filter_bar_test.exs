defmodule Web.Components.FilterBarTest do
  use ExUnit.Case, async: true

  import Web.Components.FilterBar, only: [range: 1]

  test "range says which rows a page shows" do
    page = %App.Page{page_number: 2, page_size: 50, total_entries: 1912, total_pages: 39}
    assert range(page) == "51–100 of 1,912"
  end

  test "the last page ends at the last row" do
    page = %App.Page{page_number: 5, page_size: 50, total_entries: 212, total_pages: 5}
    assert range(page) == "201–212 of 212"
  end
end
