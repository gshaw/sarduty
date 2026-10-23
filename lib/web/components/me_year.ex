defmodule Web.Components.MeYear do
  @moduledoc """
  The year a member's year page shows (`?year=`), and the menu of the years from
  `MemberRecords.years_on_team/2`. A long-standing member has many, so it is a menu.
  """

  use Web, :function_component

  @doc "The year `?year=` asks for, this year when it's missing, or a 404."
  def year!(nil, [this_year | _older]), do: this_year

  def year!(param, years) do
    case Integer.parse(param) do
      {year, ""} -> if year in years, do: year, else: raise(Web.Status.NotFound)
      _other -> raise Web.Status.NotFound
    end
  end

  attr :years, :list, required: true
  attr :year, :integer, required: true

  @doc "The year menu. Its page handles `year`, patching to `?year=`."
  def year_menu(assigns) do
    ~H"""
    <form :if={length(@years) > 1} id="years" class="mb-4" phx-change="year">
      <div class="filter-menu">
        <label for="year" class="filter-menu-label">Year</label>
        <select id="year" name="year">
          {Phoenix.HTML.Form.options_for_select(@years, @year)}
        </select>
      </div>
    </form>
    """
  end
end
