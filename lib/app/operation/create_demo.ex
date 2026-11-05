defmodule App.Operation.CreateDemo do
  @moduledoc """
  Starts a Try a demo (#857): the demo's row and the user its link logs in as. Nothing is
  built until the link is opened (App.Operation.BuildDemoTeam), so a link nobody opens
  costs a row. Web.DemoLive's button and the API (Web.DemoApiController) both call it.

  A visitor's demo: an optional name, 5 an hour per IP, and 200 live in all. A test's,
  made with the test key (`DEMO_TEST_KEY`) for a script checking a live server: no name
  needed, no limits, and it lasts the hours asked, 2 by default, 24 at most.
  """

  alias App.Accounts
  alias App.Adapter.D4H
  alias App.Model.DemoTeam
  alias App.RateLimit
  alias App.Repo
  alias App.ViewModel.DemoStartViewModel

  @ip_limit 5
  @live_limit 200
  @test_hours 2
  @max_test_hours 24

  @doc """
  `{:ok, demo}`, `{:error, changeset}` for the name, or `{:error, reason}`: `:limited`,
  `:full`, or `:off` when Try a demo is off. `opts`: `ip`, `kind` (`:visitor`
  or `:test`), `hours` for a test, `now`.
  """
  def call(params, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now(:second))
    kind = Keyword.get(opts, :kind, :visitor)

    with :ok <- check_on(),
         {:ok, form} <- DemoStartViewModel.validate(params),
         :ok <- check_limits(kind, opts[:ip], now) do
      {:ok, insert(form.name, kind, expires_at(kind, opts[:hours], now))}
    end
  end

  @doc "Whether Try a demo is on: SAR Duty's own Records key (RECORDS_SARDUTY_KEY) is set."
  def on?, do: D4H.records_sarduty_key?()

  @doc "Whether `key` is the test key, which makes test demos."
  def test_key?(key) do
    expected = Application.get_env(:sarduty, :demo_test_key)

    is_binary(expected) and expected != "" and is_binary(key) and
      Plug.Crypto.secure_compare(key, expected)
  end

  @doc "What call/2's errors say."
  def error_text(:limited), do: "Too many demos from this connection. Try again in an hour."
  def error_text(:full), do: "Try a demo is full right now. Try again tomorrow."
  def error_text(:off), do: "Try a demo is off right now. Sign up your team instead."
  def error_text(_reason), do: "The demo did not start. Try again in a few minutes."

  defp check_on, do: if(on?(), do: :ok, else: {:error, :off})

  defp check_limits(:test, _ip, _now), do: :ok

  defp check_limits(:visitor, ip, now) do
    cond do
      RateLimit.inc("demo:ip:" <> RateLimit.ip_key(ip || "unknown"), :timer.hours(1)) >
          @ip_limit ->
        {:error, :limited}

      DemoTeam.live_count(now) >= @live_limit ->
        {:error, :full}

      true ->
        :ok
    end
  end

  # A visitor's is reset to 3 days when it's built; a test's stays as asked.
  defp expires_at(:visitor, _hours, now), do: DateTime.add(now, DemoTeam.days(), :day)

  defp expires_at(:test, hours, now),
    do: DateTime.add(now, hours |> parse_hours() |> min(@max_test_hours), :hour)

  defp parse_hours(hours) when is_integer(hours) and hours > 0, do: hours

  defp parse_hours(hours) when is_binary(hours) do
    case Integer.parse(hours) do
      {n, ""} when n > 0 -> n
      _other -> @test_hours
    end
  end

  defp parse_hours(_hours), do: @test_hours

  # The row, then its user, whose email needs the row's id.
  defp insert(name, kind, expires_at) do
    {:ok, demo} =
      Repo.transaction(fn ->
        demo = Repo.insert!(%DemoTeam{kind: kind, name: name, expires_at: expires_at})
        user = Accounts.get_or_create_user(DemoTeam.visitor_email(demo))
        demo |> Ecto.Changeset.change(user_id: user.id) |> Repo.update!()
      end)

    demo
  end
end
