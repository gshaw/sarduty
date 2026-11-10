defmodule App.Worker.EmailTaxCreditLettersWorker do
  # Email for many members of the letters list (App.Operation.EmailTaxCreditLetters.run/5).
  # A retry is safe: each new letter commits with its email job, and a retry finds the
  # letter up to date and emails it once more only if its email isn't waiting. One job
  # per team and year at a time, so a double click cannot publish two letters for one
  # member.
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:team_id, :year], states: :incomplete, period: :infinity]

  alias App.Accounts.User
  alias App.Model.Team
  alias App.Operation.EmailTaxCreditLetters

  @doc """
  Queues Email for `year`'s letters of these members, by `user`; `early`, as the page
  asked first, for a year that isn't over.
  """
  def enqueue(%Team{id: team_id}, year, member_ids, %User{id: user_id}, early) do
    %{team_id: team_id, year: year, member_ids: member_ids, user_id: user_id, early: early}
    |> new()
    |> Oban.insert!()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    team = Team.get!(args["team_id"])

    EmailTaxCreditLetters.run(team, args["year"], args["member_ids"], args["user_id"],
      early: args["early"] == true
    )

    :ok
  end
end
