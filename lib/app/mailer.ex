defmodule App.Mailer do
  @moduledoc """
  Sends email through Swoosh. Every email says whose it is before deliver/2 takes it:
  for_team/2 or for_no_team/1. deliver/2 keeps a Try a demo team's (#857) in its
  Outbox instead of sending it (docs/outbox.md), so a demo sends nothing, whoever its
  members are, and it raises on an email with neither mark, so no mailer can send a
  demo's email by forgetting one.

  deliver/2 is also the one place that notes on members when the mail service blocks
  their address for good, and clears it once their email goes out again
  (docs/external-services.md#email-problems). An email to a member goes through
  to_member/2 so the clearing needs no lookup.
  """
  use Swoosh.Mailer, otp_app: :sarduty

  import Swoosh.Email

  alias App.Model.DemoTeam
  alias App.Model.Member
  alias App.Model.OutboxMessage

  @doc "Marks `email` as `team`'s, for its Outbox when the team is a demo."
  def for_team(%Swoosh.Email{} = email, team), do: put_private(email, :team_id, team.id)

  @doc """
  Addresses `email` to `member`, and carries their email problem, if any, so deliver/2
  clears it when the email goes out.
  """
  def to_member(%Swoosh.Email{} = email, %Member{} = member) do
    email
    |> to({member.name, member.email})
    |> put_private(:email_problem, member.email_problem)
  end

  @doc "Marks `email` as no team's, such as a login code, so it is always sent."
  def for_no_team(%Swoosh.Email{} = email), do: put_private(email, :team_id, :no_team)

  @doc "The team id an email was marked with, or nil for no team."
  def team_id(%Swoosh.Email{} = email) do
    case email.private[:team_id] do
      team_id when is_integer(team_id) -> team_id
      _no_team -> nil
    end
  end

  def deliver(%Swoosh.Email{} = email, config \\ []) do
    case email.private[:team_id] do
      team_id when is_integer(team_id) ->
        if DemoTeam.demo?(team_id),
          do: keep(email, team_id),
          else: note_email_problem(email, super(email, config))

      :no_team ->
        note_email_problem(email, super(email, config))

      _unmarked ->
        raise ArgumentError,
              "email #{inspect(email.subject)} has no team mark: " <>
                "pipe it through Mailer.for_team/2 or Mailer.for_no_team/1"
    end
  end

  # The adapter says which refusal is an email problem. Only an email to one address
  # says whose it is; the refusal doesn't name the recipient.
  defp note_email_problem(email, {:error, {:email_problem, problem}} = result) do
    with [address] <- recipients(email), do: Member.record_email_problem(address, problem)
    result
  end

  defp note_email_problem(%{private: %{email_problem: problem}} = email, {:ok, _} = result)
       when problem != nil do
    with [address] <- recipients(email), do: Member.clear_email_problem(address)
    result
  end

  defp note_email_problem(_email, result), do: result

  defp recipients(email),
    do: Enum.map(email.to ++ email.cc ++ email.bcc, fn {_name, address} -> address end)

  defp keep(email, team_id) do
    message = OutboxMessage.add_email!(email, team_id)
    {:ok, %{id: message.id}}
  end
end
