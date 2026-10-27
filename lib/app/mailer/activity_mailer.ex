defmodule App.Mailer.ActivityMailer do
  import Swoosh.Email

  alias App.Mailer
  alias App.Model.Activity
  alias App.Model.Member
  alias App.Model.Team
  alias Service.Format
  alias Web.ReplyLinks

  # The emails a team admin sends about an activity: a reminder to reply (#444) and an
  # update (#609). Both come from the team, with replies going to the team admin who
  # sent it: Cloudflare takes Reply-To as its API's `reply_to` field, not a header.
  # `sender` is `%{name:, email:}`, and `message` the team admin's own words, or nil.

  # The two buttons, in SAR Duty's success and secondary colours. Mail apps drop
  # stylesheets, so they're inline. Text sets no colour, so a mail app in dark mode
  # keeps it readable; a fixed grey turned dark on dark. Each button carries its own.
  @button "display:inline-block;padding:10px 16px;margin:0 8px 8px 0;border-radius:4px;font-weight:700;text-decoration:none;"
  @yes @button <> "background:#00703c;color:#ffffff;"
  @no @button <> "background:#f3f2f1;color:#0b0c0c;box-shadow:inset 0 -2px 0 #b1b4b6;"

  @doc """
  Emails a member a reminder to reply. Each button opens the reply page with its answer
  selected, which changes nothing until the member sends it (#488). It carries a
  one-click unsubscribe, which turns off the member's invitation reminders.
  """
  def deliver_reminder(
        %Member{} = member,
        %Activity{} = activity,
        %Team{} = team,
        sender,
        message
      ) do
    reminders_url = url(ReplyLinks.reminders_path(member))
    links = links(member, activity, team, reminders_url)

    member
    |> email(team, sender, reminder_subject(activity))
    |> header("List-Unsubscribe", "<#{reminders_url}>")
    |> header("List-Unsubscribe-Post", "List-Unsubscribe=One-Click")
    |> bodies(activity, team, sender, message, :ask, links)
    |> Mailer.deliver()
  end

  @doc """
  Emails a member an update, ending with where they stand (see update_ending/2). It has
  no unsubscribe: it's the team admin writing to the people on their activity.
  """
  def deliver_update(
        %Member{} = member,
        %Activity{} = activity,
        %Team{} = team,
        sender,
        message,
        ending
      ) do
    links = links(member, activity, team, nil)

    member
    |> email(team, sender, update_subject(activity))
    |> bodies(activity, team, sender, message, ending, links)
    |> Mailer.deliver()
  end

  @doc """
  How an update ends for a member, from their reply (a D4H status) and their invitation
  reminders: `:ask` with the reply buttons, `:open` with only the activity's link for
  one who turned reminders off, or `:signed_up` or `:cant_make_it` with a link to change
  it.
  """
  def update_ending("requested", %Member{invitation_reminders: false}), do: :open
  def update_ending("requested", _member), do: :ask
  def update_ending("attending", _member), do: :signed_up
  def update_ending("absent", _member), do: :cant_make_it

  @doc """
  A reminder as Send reminders shows it (#608), from the same subject and HTML that
  deliver_reminder/5 sends, as `%{subject:, html:}`. Its links go nowhere: each real one
  is signed for its member.
  """
  def reminder_preview(%Activity{} = activity, %Team{} = team, sender, message),
    do: %{
      subject: reminder_subject(activity),
      html: html(activity, team, from_name(sender), message, :ask, nowhere("#"))
    }

  @doc "An update as Send an update shows it, for one ending, like reminder_preview/4."
  def update_preview(%Activity{} = activity, %Team{} = team, sender, message, ending),
    do: %{
      subject: update_subject(activity),
      html: html(activity, team, from_name(sender), message, ending, nowhere(nil))
    }

  defp reminder_subject(activity), do: "Will you be there? #{activity.title}"
  defp update_subject(activity), do: "Update: #{activity.title}"

  defp email(member, team, sender, subject) do
    new()
    |> to({member.name, member.email})
    |> from({team.name, "noreply@sarduty.com"})
    |> reply_to({sender.name || "", sender.email})
    |> subject(subject)
  end

  defp bodies(email, activity, team, sender, message, ending, links) do
    email
    |> text_body(text(activity, team, from_name(sender), message, ending, links))
    |> html_body(html(activity, team, from_name(sender), message, ending, links))
  end

  defp from_name(sender), do: sender.name || sender.email

  defp url(path), do: Web.Endpoint.url() <> path

  # Each reply link opens the reply page with its answer selected.
  defp links(member, activity, team, reminders_url) do
    %{
      yes: url(ReplyLinks.reply_path(member, activity, :yes)),
      no: url(ReplyLinks.reply_path(member, activity, :no)),
      activity: url("/teams/#{team.subdomain}/activities/#{activity.id}"),
      reminders: reminders_url
    }
  end

  # An update has no unsubscribe link, so its preview has none either.
  defp nowhere(reminders), do: %{yes: "#", no: "#", activity: "#", reminders: reminders}

  defp facts(activity, team) do
    Enum.reject(
      [Format.datetime_medium(activity.started_at, team.timezone), activity.address],
      &(&1 in [nil, ""])
    )
  end

  defp footer(from_name),
    do: "#{from_name}, a team admin, sent this email. Reply to this email to reach them."

  # Where the member stands, and the link that changes it.
  defp standing(:signed_up), do: {"You're signed up.", :no}
  defp standing(:cant_make_it), do: {"You said you can't make it.", :yes}

  defp text(activity, team, from_name, message, ending, links) do
    """
    #{team.name}

    #{activity.title}
    #{Enum.join(facts(activity, team), "\n")}
    #{if message, do: "\n" <> message <> "\n"}
    #{ending_text(ending, links)}
    Open activity (log in):
    #{links.activity}

    #{footer(from_name)}
    #{if links.reminders, do: "\nTurn off invitation reminders:\n" <> links.reminders <> "\n"}\
    """
  end

  defp ending_text(:ask, links) do
    """
    Will you be there?

    I'll be there:
    #{links.yes}

    Can't make it:
    #{links.no}
    """
  end

  defp ending_text(:open, _links), do: ""

  defp ending_text(ending, links) do
    {line, answer} = standing(ending)

    """
    #{line}

    Change your reply:
    #{links[answer]}
    """
  end

  defp html(activity, team, from_name, message, ending, links) do
    """
    <p style="font-size:14px;margin:0 0 4px">#{escape(team.name)}</p>
    <h1 style="font-size:24px;margin:0 0 8px">#{escape(activity.title)}</h1>
    #{Enum.map_join(facts(activity, team), "\n", &"<p style=\"margin:0\">#{escape(&1)}</p>")}
    #{message_html(message)}
    #{ending_html(ending, links)}
    <p style="margin:16px 0 0"><a href="#{escape(links.activity)}">Open activity</a> (log in)</p>
    <hr style="border:0;border-top:1px solid #b1b4b6;margin:32px 0 16px">
    <p style="font-size:14px;margin:0 0 8px">#{escape(footer(from_name))}</p>
    #{if links.reminders, do: ~s(<p style="font-size:14px;margin:0"><a href="#{escape(links.reminders)}">Turn off invitation reminders</a></p>)}
    """
  end

  defp ending_html(:ask, links) do
    """
    <p style="margin:24px 0 12px"><strong>Will you be there?</strong></p>
    <p style="margin:0"><a href="#{escape(links.yes)}" style="#{@yes}">I'll be there</a><a href="#{escape(links.no)}" style="#{@no}">Can't make it</a></p>
    """
  end

  defp ending_html(:open, _links), do: ""

  defp ending_html(ending, links) do
    {line, answer} = standing(ending)

    ~s(<p style="margin:24px 0 0"><strong>#{escape(line)}</strong> <a href="#{escape(links[answer])}">Change your reply</a></p>)
  end

  # Plain text, escaped, its line breaks kept. Some mail apps drop white-space, so each
  # line break is a <br>.
  defp message_html(nil), do: ""

  defp message_html(message) do
    lines = message |> String.split("\n") |> Enum.map_join("<br>", &escape/1)
    ~s(<p style="margin:24px 0 0">#{lines}</p>)
  end

  defp escape(string), do: string |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
