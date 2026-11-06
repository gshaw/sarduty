defmodule App.Mailer do
  @moduledoc """
  Sends email through Swoosh. A team's email goes through for_team/3 first, which marks
  it with the team and, on a Try a demo team (#857), sends it to the visitor instead.
  deliver/2 then refuses a demo team's email to anyone but its visitor, as a backstop
  for a mailer that forgot.
  """
  use Swoosh.Mailer, otp_app: :sarduty

  import Swoosh.Email

  alias App.Model.DemoTeam

  require Logger

  @doc """
  Marks `email` as `team`'s. On a demo team, it goes to the visitor alone, with [Demo]
  before the subject and a first line saying whose copy it is: `for` is the member's
  name for a member's email, or `:team_admins`.
  """
  def for_team(%Swoosh.Email{} = email, team, for) do
    email = put_private(email, :team_id, team.id)

    case DemoTeam.for_team(team) do
      nil -> email
      demo -> to_visitor(email, demo, note(for))
    end
  end

  defp to_visitor(email, demo, note) do
    email = %{email | to: [{demo.name, demo.email}], cc: [], bcc: []}
    email = subject(email, "[Demo] " <> email.subject)

    email =
      if email.text_body, do: text_body(email, note <> "\n\n" <> email.text_body), else: email

    if email.html_body,
      do: html_body(email, note_html(note) <> email.html_body),
      else: email
  end

  defp note(:team_admins),
    do: "This is your demo. Its team admins would get this email, and it came to you instead."

  defp note(:help),
    do:
      "This is your demo. Get help would send this to the people you ticked, and it came to you instead."

  defp note({:replies, name}) do
    first = name |> String.split(" ") |> hd()
    note(name) <> " Its buttons answer for #{first}, so you see the reply land."
  end

  defp note(name) when is_binary(name),
    do: "This is your demo. #{name} would get this email, and it came to you instead."

  defp note_html(note),
    do:
      ~s(<p style="margin:0 0 16px;padding:8px 12px;border-left:4px solid #1d70b8">#{Plug.HTML.html_escape(note)}</p>\n)

  def deliver(%Swoosh.Email{} = email, config \\ []) do
    case check_demo(email) do
      :ok -> super(email, config)
      error -> error
    end
  end

  defp check_demo(%Swoosh.Email{private: %{team_id: team_id}} = email) do
    case DemoTeam.for_team(team_id) do
      nil ->
        :ok

      demo ->
        if Enum.all?(email.to ++ email.cc ++ email.bcc, &same_email?(&1, demo.email)) do
          :ok
        else
          Logger.error("Refused a demo team's email to someone but its visitor (team #{team_id})")
          {:error, :demo_recipient}
        end
    end
  end

  defp check_demo(_email), do: :ok

  defp same_email?({_name, address}, email),
    do: String.downcase(address) == String.downcase(email)
end
