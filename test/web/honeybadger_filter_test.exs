defmodule Web.HoneybadgerFilterTest do
  use ExUnit.Case, async: true

  test "filters secrets nested in form params" do
    params = %{
      "user" => %{"email" => "a@example.com", "password" => "secret"},
      "team" => %{"access_key" => "d4h-key"},
      "token" => "reset-token"
    }

    assert Web.HoneybadgerFilter.filter_params(params) == %{
             "user" => %{"email" => "a@example.com", "password" => "[FILTERED]"},
             "team" => %{"access_key" => "[FILTERED]"},
             "token" => "[FILTERED]"
           }
  end
end
