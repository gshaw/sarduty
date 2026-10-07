alias App.Model.Event
alias App.Model.Member
alias App.Model.TaxCreditLetter
alias App.Model.Team
alias App.Operation.CreateTaxCreditLetter
alias App.Operation.EmailTaxCreditLetter
alias App.Repo

defmodule App.Operation.CreateTaxCreditLetters do
  import Ecto.Query

  @doc """
  Creates and emails a letter for `year` to each of these members who has none yet
  (#195). Runs in `App.Worker.CreateTaxCreditLettersWorker`. Records the counts as an
  event, tells the letter list through `topic/1`, and returns the summary.
  """
  def call(%Team{} = team, year, member_ids, user_id \\ nil) do
    members =
      Member
      |> where([m], m.team_id == ^team.id and m.id in ^member_ids)
      |> order_by([m], asc: m.name)
      |> Repo.all()

    results =
      for member <- pick(members, letter_member_ids(team, year)) do
        letter = CreateTaxCreditLetter.call(team: team, member_id: member.id, year: year)
        {member, EmailTaxCreditLetter.call(letter)}
      end

    summary = summarize(results, year)
    record_event(team, user_id, summary)
    Phoenix.PubSub.broadcast(App.PubSub, topic(team.id), {:tax_credit_letters_sent, summary})
    summary
  end

  def topic(team_id), do: "tax_credit_letters:#{team_id}"

  @doc "The members who get a letter: those with none for the year yet."
  def pick(members, letter_member_ids) do
    have = MapSet.new(letter_member_ids)
    Enum.reject(members, &MapSet.member?(have, &1.id))
  end

  @doc "Counts, and who had no email or whose email did not send, from `{member, result}`."
  def summarize(results, year) do
    %{
      year: year,
      created: length(results),
      emailed: Enum.count(results, fn {_member, result} -> result == :ok end),
      no_email: for({member, {:error, :no_email}} <- results, do: member),
      failed:
        for(
          {member, {:error, reason}} <- results,
          reason != :no_email,
          do: member
        )
    }
  end

  defp letter_member_ids(team, year) do
    TaxCreditLetter
    |> join(:inner, [tcl], m in assoc(tcl, :member))
    |> where([tcl, m], m.team_id == ^team.id and tcl.year == ^year)
    |> select([tcl], tcl.member_id)
    |> Repo.all()
  end

  # Ids and counts only, never names or emails, as Event asks.
  defp record_event(team, user_id, summary) do
    Event.record!(:tax_credit_letters_sent,
      team_id: team.id,
      user_id: user_id,
      data: %{
        year: summary.year,
        created: summary.created,
        emailed: summary.emailed,
        no_email_member_ids: Enum.map(summary.no_email, & &1.id),
        failed_member_ids: Enum.map(summary.failed, & &1.id)
      }
    )
  end
end
