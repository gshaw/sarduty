defmodule Web.HoneybadgerFilterTest do
  use ExUnit.Case, async: true

  alias Web.HoneybadgerFilter

  test "filters secrets nested in form params" do
    params = %{
      "user" => %{"email" => "a@example.com", "password" => "secret"},
      "team" => %{"access_key" => "d4h-key"},
      "token" => "reset-token"
    }

    assert HoneybadgerFilter.filter_params(params) == %{
             "user" => %{"email" => "a@example.com", "password" => "[FILTERED]"},
             "team" => %{"access_key" => "[FILTERED]"},
             "token" => "[FILTERED]"
           }
  end

  test "filters any key containing key, token or code" do
    params = %{
      "team" => %{"new_d4h_access_key" => "d4h-key", "name" => "NSR"},
      "user" => %{"email" => "a@example.com", "code" => "123456"},
      "pushToken" => "apns"
    }

    assert HoneybadgerFilter.filter_params(params) == %{
             "team" => %{"new_d4h_access_key" => "[FILTERED]", "name" => "NSR"},
             "user" => %{"email" => "a@example.com", "code" => "[FILTERED]"},
             "pushToken" => "[FILTERED]"
           }
  end

  test "cuts tokens and codes from an error's path, headers and referrer" do
    notice = %Honeybadger.Notice{
      error: %{message: "boom"},
      breadcrumbs: %{trail: []},
      notifier: %{},
      server: %{},
      correlation_context: %{},
      request: %{
        url: "/attendance/secret-token",
        params: %{"token" => "secret-token"},
        session: %{},
        context: %{},
        cgi_data: %{
          "HTTP_HOST" => "sarduty.com",
          "PATH_INFO" => "attendance/secret-token",
          "ORIGINAL_FULLPATH" => "/attendance/secret-token",
          "HTTP_REFERER" => "https://sarduty.com/s/SHORTCODE"
        }
      }
    }

    %{request: request} = HoneybadgerFilter.filter(notice)

    assert request.url == "/attendance/[FILTERED]"
    assert request.params == %{"token" => "[FILTERED]"}
    assert request.cgi_data["PATH_INFO"] == "attendance/[FILTERED]"
    assert request.cgi_data["ORIGINAL_FULLPATH"] == "/attendance/[FILTERED]"
    assert request.cgi_data["HTTP_REFERER"] == "https://sarduty.com/s/[FILTERED]"
    refute inspect(request) =~ "secret-token"
  end

  test "cuts card codes from Insights request events" do
    conn = %Plug.Conn{host: "verify.sarduty.com"}
    data = %{request_path: "/K7Q4M2XA/photo", params: %{"code" => "K7Q4M2XA"}}

    filtered = HoneybadgerFilter.filter_telemetry_event(data, %{conn: conn}, [:phoenix])

    assert filtered.request_path == "/[FILTERED]/photo"
    refute inspect(filtered) =~ "K7Q4M2XA"
  end

  test "cuts tokens from a LiveView's URL in Insights" do
    data = %{url: "https://sarduty.com/attendance/secret-token", params: %{}}

    filtered = HoneybadgerFilter.filter_telemetry_event(data, %{}, [:phoenix])

    assert filtered.url == "https://sarduty.com/attendance/[FILTERED]"
  end
end
