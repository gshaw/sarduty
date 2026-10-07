defmodule App.Worker.CreateTaxCreditLettersWorker do
  # One attempt: a retry would skip the letters already made, so their emails that
  # failed would never be tried again. The summary lists them instead. One job per team
  # and year at a time, so a double click cannot make two letters for one member.
  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [keys: [:team_id, :year], states: :incomplete, period: :infinity]

  alias App.Model.Team
  alias App.Operation.CreateTaxCreditLetters

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    team = Team.get!(args["team_id"])
    CreateTaxCreditLetters.call(team, args["year"], args["member_ids"], args["user_id"])
    :ok
  end
end
