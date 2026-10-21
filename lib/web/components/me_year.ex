defmodule Web.Components.MeYear do
  @moduledoc """
  The year a member's Activities and Hours pages show (`?year=`), and the switch between
  the years they attended in, from `MemberRecords.years/2`.
  """

  use Web, :function_component

  import Web.Components.ViewSwitch

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
  attr :path, :string, required: true, doc: "the page's path, without the year"

  def year_switch(assigns) do
    ~H"""
    <.view_switch :if={length(@years) > 1} id="years" label="Year">
      <:view
        :for={year <- @years}
        id={"year-#{year}"}
        patch={"#{@path}?year=#{year}"}
        current={year == @year}
      >
        {year}
      </:view>
    </.view_switch>
    """
  end
end
