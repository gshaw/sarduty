alias App.Model.Event
alias App.Model.Member
alias App.Model.TaxCreditLetter
alias App.Model.Team
alias App.Operation.CreateTaxCreditLetter
alias App.Operation.EmailTaxCreditLetter
alias App.Repo
alias App.Worker.EmailTaxCreditLetterWorker

defmodule App.Operation.CreateTaxCreditLetters do
  import Ecto.Query

  @doc """
  Creates a letter for `year` for each of these members who has none yet (#195), each
  with its email job (App.Worker.EmailTaxCreditLetterWorker) in one transaction. Runs in
  `App.Worker.CreateTaxCreditLettersWorker`. Records the counts as an event, tells the
  letter list through `topic/1`, and returns the summary. Each email job tells the list
  again when it's done.
  """
  def call(%Team{} = team, year, member_ids, user_id \\ nil) do
    members =
      Member
      |> where([m], m.team_id == ^team.id and m.id in ^member_ids)
      |> order_by([m], asc: m.name)
      |> Repo.all()

    results =
      for member <- pick(members, letter_member_ids(team, year)), do: create(team, member, year)

    summary = summarize(results, year)
    record_event(team, user_id, summary)
    Phoenix.PubSub.broadcast(App.PubSub, topic(team.id), {:tax_credit_letters_sent, summary})
    summary
  end

  def topic(team_id), do: "tax_credit_letters:#{team_id}"

  # A letter and its email job commit together, so a retry of the whole run makes only
  # the letters still missing, and no email is lost.
  defp create(team, member, year) do
    {:ok, result} =
      Repo.transaction(fn ->
        letter = CreateTaxCreditLetter.call(team: team, member_id: member.id, year: year)

        if member.email in [nil, ""] do
          {member, :no_email}
        else
          letter
          |> TaxCreditLetter.set_email_status!(:sending)
          |> EmailTaxCreditLetterWorker.enqueue()

          {member, :emailing}
        end
      end)

    result
  end

  @doc """
  Emails a letter whose email is waiting, for its job, and tells the letter list. A
  refusal is `{:error, reason}`, so the job tries again; on the `last?` attempt the
  letter is marked failed first. A letter no longer waiting is `{:cancel, reason}`.
  """
  def email(letter_id, last?) do
    case TaxCreditLetter.get_sending(letter_id) do
      nil -> {:cancel, "no letter waiting for its email"}
      letter -> letter |> EmailTaxCreditLetter.call() |> finish_email(letter, last?)
    end
  end

  defp finish_email(:ok, letter, _last?), do: broadcast_emailed(letter)

  defp finish_email({:error, :no_email}, letter, _last?) do
    TaxCreditLetter.set_email_status!(letter, :failed)
    broadcast_emailed(letter)
    {:cancel, "the member has no email"}
  end

  defp finish_email({:error, reason}, letter, last?) do
    if last? do
      TaxCreditLetter.set_email_status!(letter, :failed)
      broadcast_emailed(letter)
    end

    {:error, reason}
  end

  defp broadcast_emailed(letter) do
    Phoenix.PubSub.broadcast(
      App.PubSub,
      topic(letter.member.team_id),
      {:tax_credit_letter_emailed, letter.id}
    )
  end

  @doc "The members who get a letter: those with none for the year yet."
  def pick(members, letter_member_ids) do
    have = MapSet.new(letter_member_ids)
    Enum.reject(members, &MapSet.member?(have, &1.id))
  end

  @doc "Counts, and who had no email, from `{member, :emailing | :no_email}`."
  def summarize(results, year) do
    %{
      year: year,
      created: length(results),
      emailing: Enum.count(results, fn {_member, result} -> result == :emailing end),
      no_email: for({member, :no_email} <- results, do: member)
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
        emailing: summary.emailing,
        no_email_member_ids: Enum.map(summary.no_email, & &1.id)
      }
    )
  end
end
