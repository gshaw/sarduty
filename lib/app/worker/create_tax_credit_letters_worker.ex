defmodule App.Worker.CreateTaxCreditLettersWorker do
  # A retry is safe: each letter commits with its email job, so a retry makes only the
  # letters still missing. One job per team and year at a time, so a double click cannot
  # make two letters for one member.
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:team_id, :year], states: :incomplete, period: :infinity]

  alias App.Accounts.User
  alias App.Model.Team
  alias App.Operation.CreateTaxCreditLetters

  @doc "Queues letters for `year` for these members, sent by `user`."
  def enqueue(%Team{id: team_id}, year, member_ids, %User{id: user_id}) do
    %{team_id: team_id, year: year, member_ids: member_ids, user_id: user_id}
    |> new()
    |> Oban.insert!()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    team = Team.get!(args["team_id"])
    CreateTaxCreditLetters.call(team, args["year"], args["member_ids"], args["user_id"])
    :ok
  end
end
