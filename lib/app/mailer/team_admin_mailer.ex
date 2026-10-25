defmodule App.Mailer.TeamAdminMailer do
  @moduledoc """
  Rare notices to a team's team admins (#512): the team joined or left an organization,
  and its ID cards were turned on or off. One email per team admin, the emails
  `TeamSummary.team_admin_emails/2` lists, sent inline right after the change; a failed
  send doesn't undo it. Replies reach SAR Duty at support@sarduty.com.
  """
  import Swoosh.Email

  alias App.Mailer
  alias App.Model.Activity
  alias App.Model.Organization
  alias App.Model.Team
  alias App.ViewData.TeamSummary

  @support "support@sarduty.com"

  @doc "The team is now in the organization."
  def deliver_joined(%Team{} = team, %Organization{} = organization, now) do
    deliver(team, now, "#{team.name} is now in #{organization.short_name}", [
      "#{team.name} is now in #{organization.name} on SAR Duty.",
      [
        "The back of your team's ID cards names #{organization.name}.",
        joined_hours_line(organization),
        "#{organization.short_name}'s organization admins can turn your ID cards on or off. Team admins in team settings lists them."
      ]
    ])
  end

  @doc "The team is no longer in the organization."
  def deliver_left(%Team{} = team, %Organization{} = organization, now) do
    deliver(team, now, "#{team.name} is no longer in #{organization.short_name}", [
      "#{team.name} is no longer in #{organization.name} on SAR Duty.",
      Enum.reject(
        [
          "The back of your team's ID cards no longer names #{organization.name}.",
          left_hours_line(organization),
          "Your ID cards stay on or off as they are."
        ],
        &is_nil/1
      )
    ])
  end

  @doc "Someone turned the team's ID cards on or off. `revoked` is how many were cancelled."
  def deliver_id_cards(%Team{} = team, enabled, actor_email, revoked, now) do
    if enabled do
      deliver(team, now, "ID cards are on for #{team.name}", [
        "#{actor_email} turned on ID cards for #{team.name} on SAR Duty. Members can add one from Your membership."
      ])
    else
      cards = Service.Format.count(revoked, one: "Its %d card is", many: "Its %d cards are")

      deliver(team, now, "ID cards are off for #{team.name}", [
        "#{actor_email} turned off ID cards for #{team.name} on SAR Duty. #{cards} cancelled. Turning ID cards back on does not bring these cards back. Members add new ones."
      ])
    end
  end

  # The kinds the organization names, and the ones it leaves to the team.
  defp joined_hours_line(organization) do
    {set, blank} = hours_kinds(organization)

    named =
      Enum.map_join(set, ", ", fn {kind, tag} -> "#{tag} (#{Activity.hours_kind_name(kind)})" end)

    keeps =
      case blank do
        [] ->
          ""

        [kind] ->
          " Your team keeps its own tag for #{Activity.hours_kind_name(kind)}."

        kinds ->
          " Your team keeps its own tags for #{Enum.map_join(kinds, " and ", &Activity.hours_kind_name/1)}."
      end

    if set == [],
      do: "Your tax credit letters keep your team's own hours tags.",
      else:
        "Your tax credit letters count #{organization.short_name}'s hours tags: #{named}.#{keeps} Letters already made keep their hours."
  end

  defp left_hours_line(organization) do
    case hours_kinds(organization) do
      {[], _blank} ->
        nil

      {_set, _blank} ->
        "Your tax credit letters go back to your team's own hours tags. Letters already made keep their hours."
    end
  end

  defp hours_kinds(organization) do
    tags = Activity.organization_hours_tags(organization)
    kinds = [:primary, :secondary, :other]
    set = for kind <- kinds, tags[kind], do: {kind, tags[kind]}
    blank = for kind <- kinds, is_nil(tags[kind]), do: kind
    {set, blank}
  end

  defp deliver(team, now, subject, paragraphs) do
    body = paragraphs |> Enum.map_join("\n\n", &paragraph/1)
    body = body <> "\n\nReply to this email to reach SAR Duty.\n"

    for email <- recipients(team, now) do
      new()
      |> to(email)
      |> from({"SAR Duty", "noreply@sarduty.com"})
      |> reply_to(@support)
      |> subject(subject)
      |> text_body(body)
      |> Mailer.deliver()
    end

    :ok
  end

  defp paragraph(lines) when is_list(lines), do: Enum.map_join(lines, "\n", &("- " <> &1))
  defp paragraph(text), do: text

  @doc "Who gets these: the team's team admins, one per email."
  def recipients(%Team{} = team, now), do: TeamSummary.team_admin_emails([team], now)[team.id]
end
