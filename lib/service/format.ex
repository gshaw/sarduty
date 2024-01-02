defmodule Service.Format do
  @moduledoc """
    Useful functions for formatting data into strings.
  """

  def short_date(date) do
    Calendar.strftime(date, "%x")
  end
end
