defmodule App.Mailer do
  @moduledoc """
  Sends email through Swoosh. A team's email goes through for_team/2 first, which marks
  it with the team. deliver/2 keeps a Try a demo team's (#857) in its Outbox instead of
  sending it (docs/outbox.md), so a demo sends nothing, whoever its members are.
  """
  use Swoosh.Mailer, otp_app: :sarduty

  import Swoosh.Email

  alias App.Model.DemoTeam
  alias App.Model.OutboxMessage

  @doc "Marks `email` as `team`'s, for its Outbox when the team is a demo."
  def for_team(%Swoosh.Email{} = email, team), do: put_private(email, :team_id, team.id)

  def deliver(%Swoosh.Email{} = email, config \\ []) do
    case email.private[:team_id] do
      team_id when is_integer(team_id) ->
        if DemoTeam.demo?(team_id), do: keep(email, team_id), else: super(email, config)

      nil ->
        super(email, config)
    end
  end

  defp keep(email, team_id) do
    message = OutboxMessage.add_email!(email, team_id)
    {:ok, %{id: message.id}}
  end
end
