defmodule App.Mailer.ReminderMailer do
  import Swoosh.Email

  alias App.Mailer
  alias App.Model.Activity
  alias App.Model.Member
  alias App.Model.Team
  alias Service.Format
  alias Web.ReplyLinks

  # The two buttons, in SAR Duty's success and secondary colours. Mail apps drop
  # stylesheets, so they're inline.
  @button "display:inline-block;padding:10px 16px;margin:0 8px 8px 0;border-radius:4px;font-weight:700;text-decoration:none;"
  @yes @button <> "background:#00703c;color:#ffffff;"
  @no @button <> "background:#f3f2f1;color:#0b0c0c;box-shadow:inset 0 -2px 0 #b1b4b6;"

  @doc """
  Emails a member a reminder to reply to an activity (#444), from the team, with
  replies going to the team admin who sent it: Cloudflare takes Reply-To as its API's
  `reply_to` field, not a header. Each button opens the reply page with its answer
  selected, which changes nothing until the member sends it (#488). It carries a
  one-click unsubscribe, which turns off the member's invitation reminders. `sender` is
  `%{name:, email:}`.
  """
  def deliver(%Member{} = member, %Activity{} = activity, %Team{} = team, sender) do
    reply_urls = reply_urls(member, activity)
    reminders_url = url(ReplyLinks.reminders_path(member))
    activity_url = url("/teams/#{team.subdomain}/activities/#{activity.id}")
    from_name = sender.name || sender.email

    new()
    |> to({member.name, member.email})
    |> from({team.name, "noreply@sarduty.com"})
    |> reply_to({sender.name || "", sender.email})
    |> subject("Will you be there? #{activity.title}")
    |> header("List-Unsubscribe", "<#{reminders_url}>")
    |> header("List-Unsubscribe-Post", "List-Unsubscribe=One-Click")
    |> text_body(text(activity, team, from_name, reply_urls, activity_url, reminders_url))
    |> html_body(html(activity, team, from_name, reply_urls, activity_url, reminders_url))
    |> Mailer.deliver()
  end

  defp url(path), do: Web.Endpoint.url() <> path

  # A link per button, each opening the reply page with its answer selected.
  defp reply_urls(member, activity),
    do: Map.new([:yes, :no], &{&1, url(ReplyLinks.reply_path(member, activity, &1))})

  defp facts(activity, team) do
    Enum.reject(
      [Format.datetime_medium(activity.started_at, team.timezone), activity.address],
      &(&1 in [nil, ""])
    )
  end

  defp footer(from_name),
    do: "#{from_name}, a team admin, sent this email. Reply to this email to reach them."

  defp text(activity, team, from_name, reply_urls, activity_url, reminders_url) do
    """
    #{team.name}

    #{activity.title}
    #{Enum.join(facts(activity, team), "\n")}

    Will you be there?

    I'll be there:
    #{reply_urls.yes}

    Can't make it:
    #{reply_urls.no}

    Open activity (log in):
    #{activity_url}

    #{footer(from_name)}

    Turn off invitation reminders:
    #{reminders_url}
    """
  end

  defp html(activity, team, from_name, reply_urls, activity_url, reminders_url) do
    """
    <p style="color:#505a5f;margin:0 0 4px">#{escape(team.name)}</p>
    <h1 style="font-size:24px;margin:0 0 8px">#{escape(activity.title)}</h1>
    #{Enum.map_join(facts(activity, team), "\n", &"<p style=\"margin:0\">#{escape(&1)}</p>")}
    <p style="margin:24px 0 12px"><strong>Will you be there?</strong></p>
    <p style="margin:0"><a href="#{escape(reply_urls.yes)}" style="#{@yes}">I'll be there</a><a href="#{escape(reply_urls.no)}" style="#{@no}">Can't make it</a></p>
    <p style="margin:16px 0 0"><a href="#{escape(activity_url)}">Open activity</a> <span style="color:#505a5f">(log in)</span></p>
    <hr style="border:0;border-top:1px solid #b1b4b6;margin:32px 0 16px">
    <p style="color:#505a5f;font-size:14px;margin:0 0 8px">#{escape(footer(from_name))}</p>
    <p style="font-size:14px;margin:0"><a href="#{escape(reminders_url)}">Turn off invitation reminders</a></p>
    """
  end

  defp escape(string), do: string |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
