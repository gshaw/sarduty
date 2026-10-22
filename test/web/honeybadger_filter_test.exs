defmodule Web.HoneybadgerFilterTest do
  use ExUnit.Case, async: true

  alias App.Model.Member
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

  test "keeps a changeset error's errors and cuts the member details after them (#421)" do
    changeset =
      Member.build_changeset(%Member{}, %{
        team_id: 3,
        d4h_member_id: 59_778,
        email: "alex@example.com",
        phone: "16045550100",
        address: "1 Example St"
      })

    message =
      Exception.message(%Ecto.InvalidChangesetError{action: :insert, changeset: changeset})

    filtered = HoneybadgerFilter.filter_error_message(message)

    assert filtered =~ "could not perform insert because changeset is invalid."
    assert filtered =~ "name: [{\"can't be blank\""

    for detail <- ["alex@example.com", "16045550100", "1 Example St"] do
      assert message =~ detail
      refute filtered =~ detail
    end

    assert HoneybadgerFilter.filter_error_message("Database busy") == "Database busy"
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

  test "never sends a LiveView's assigns to Insights" do
    data = %{view: "Web.AttendanceLinkLive", assigns: %{members: [%{address: "1 Main St"}]}}

    filtered = HoneybadgerFilter.filter_telemetry_event(data, %{}, [:phoenix, :live_view])

    refute Map.has_key?(filtered, :assigns)
    assert filtered.view == "Web.AttendanceLinkLive"
  end

  test "cuts tokens from a LiveView's URL in Insights" do
    data = %{url: "https://sarduty.com/attendance/secret-token", params: %{}}

    filtered = HoneybadgerFilter.filter_telemetry_event(data, %{}, [:phoenix])

    assert filtered.url == "https://sarduty.com/attendance/[FILTERED]"
  end
end
