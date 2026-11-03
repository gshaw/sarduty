defmodule App.Operation.RequestDemo do
  @moduledoc """
  Try a demo's form (#857): saves the visitor's name and email and emails a link with a
  code. Nothing is built until the link is opened (App.Operation.BuildDemoTeam), so an
  email nobody opens costs nothing. The email holds no name, so a bot can't use the name
  field to send text to someone else's address.

  One demo per email: asking again sends a new code to the same demo. 5 requests an hour
  per IP, and 200 live demos in all.
  """

  alias App.Mailer.DemoMailer
  alias App.Model.DemoTeam
  alias App.RateLimit
  alias App.Repo
  alias App.ViewModel.DemoRequestViewModel

  @ip_limit 5
  @live_limit 200

  @doc """
  `{:ok, demo}` once the email is sent, `{:error, changeset}` for the form, or
  `{:error, reason}`: `:limited`, `:full`, or `:no_demo_key` when Try a demo is off.
  """
  def call(params, ip, now \\ DateTime.utc_now(:second)) do
    with :ok <- check_on(),
         {:ok, form} <- DemoRequestViewModel.validate(params),
         :ok <- check_ip(ip),
         {:ok, demo} <- find_or_add(form, now) do
      {code, changes} = DemoTeam.new_code(demo, now)
      demo = demo |> Ecto.Changeset.change(changes) |> Repo.update!()

      with {:ok, _sent} <- DemoMailer.deliver_link(demo, code), do: {:ok, demo}
    end
  end

  @doc "Whether Try a demo is on: Records' demo key is set."
  def on?, do: Application.get_env(:sarduty, :records_demo_key) not in [nil, ""]

  @doc "What call/3's errors say."
  def error_text(:limited), do: "Too many demos from this connection. Try again in an hour."
  def error_text(:full), do: "Try a demo is full right now. Try again tomorrow."
  def error_text(:no_demo_key), do: "Try a demo is off right now. Sign up your team instead."
  def error_text(_reason), do: "The email did not send. Try again in a few minutes."

  defp check_on, do: if(on?(), do: :ok, else: {:error, :no_demo_key})

  defp check_ip(ip) do
    if RateLimit.inc("demo:ip:" <> RateLimit.ip_key(ip || "unknown"), :timer.hours(1)) <=
         @ip_limit,
       do: :ok,
       else: {:error, :limited}
  end

  # A demo not yet opened takes the newest name; a built one keeps its team admin's.
  defp find_or_add(form, now) do
    case DemoTeam.get_by_email(form.email) do
      %DemoTeam{team_id: nil} = demo ->
        {:ok, demo |> Ecto.Changeset.change(name: form.name) |> Repo.update!()}

      %DemoTeam{} = demo ->
        {:ok, demo}

      nil ->
        if DemoTeam.live_count(now) >= @live_limit do
          {:error, :full}
        else
          {:ok,
           Repo.insert!(%DemoTeam{
             name: form.name,
             email: form.email,
             expires_at: DateTime.add(now, DemoTeam.days(), :day)
           })}
        end
    end
  end
end
