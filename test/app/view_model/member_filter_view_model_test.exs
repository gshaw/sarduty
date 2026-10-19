defmodule App.ViewModel.MemberFilterViewModelTest do
  use ExUnit.Case, async: true

  alias App.ViewModel.MemberFilterViewModel

  test "the Period filter takes years and the rolling periods it offers" do
    for period <- ~w(all 2026 30d 60d 90d 180d 365d),
        do: assert({:ok, _, _} = MemberFilterViewModel.validate(%{"when" => period}))

    for period <- ~w(7d 90 d last-year),
        do: assert({:error, _} = MemberFilterViewModel.validate(%{"when" => period}))
  end
end
