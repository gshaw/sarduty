defmodule Web.FormSubmitTest do
  @moduledoc """
  A LiveView form with phx-change but no phx-submit posts itself when someone presses
  Enter in a text box, and the post gets a 404 (#333). Filter forms use
  <.filter_form>, which sets both.
  """
  use ExUnit.Case, async: true

  @root "../.." |> Path.expand(__DIR__)

  test "every form with phx-change also has phx-submit" do
    for file <- @root |> Path.join("lib/web/**/*.{ex,heex}") |> Path.wildcard(),
        [tag] <- Regex.scan(~r/<\.?form\b[^>]*>/s, File.read!(file)),
        tag =~ "phx-change" do
      assert tag =~ "phx-submit",
             "#{Path.relative_to(file, @root)}: #{tag} has phx-change but no phx-submit"
    end
  end
end
