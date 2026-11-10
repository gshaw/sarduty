alias App.Accounts.User
alias App.Model.Event
alias App.Model.Member
alias App.Model.PublishedPDF
alias App.Model.TaxCreditLetter
alias App.Model.Team
alias App.Operation.EmailTaxCreditLetter
alias App.Operation.PrintTaxCreditLetter
alias App.Operation.PublishTaxCreditLetter
alias App.Operation.ReadDocument
alias App.Repo
alias App.Worker.EmailTaxCreditLettersWorker
alias App.Worker.EmailTaxCreditLetterWorker

defmodule App.Operation.EmailTaxCreditLetters do
  @moduledoc """
  Email, the one way a tax credit letter reaches its member (#995): each member gets
  their latest letter for the year as a PDF. A member with no letter, or one out of date
  (TaxCreditLetter.changes/4), gets a new one published first, so nobody keeps a letter
  that verifies as Replaced. An up-to-date letter goes again. A member with no email
  gets the letter published, on Your membership only, and one with no hours that year
  gets nothing.

  It refuses a year that isn't over in the team's time zone: its letters would need
  publishing again once it ends. A letter that needs a value the team left blank isn't
  published (PublishTaxCreditLetter), and so isn't emailed.

  One member, from the letter page, publishes and emails at once (`call_one/5`). Many,
  from the letters list, run in a job (App.Worker.EmailTaxCreditLettersWorker), since
  each new letter prints a PDF, and each email has its own job
  (App.Worker.EmailTaxCreditLetterWorker), which tells the list through `topic/1`.
  """
  import Ecto.Query

  @doc "The letter list's PubSub topic for the team's letters."
  def topic(team_id), do: "tax_credit_letters:#{team_id}"

  @doc """
  What Email does for a member, from where their letter is. Pure.

  - `:first`: no letter yet, so it publishes one, then emails it.
  - `:replace`: out of date, so it publishes a new one, then emails it.
  - `:failed`: emails the letter whose email did not send.
  - `:not_emailed`: emails the letter, never emailed before.
  - `:again`: emails an emailed, up-to-date letter again.
  - nil: not offered. The member has no hours that year, or no email and a letter up to
    date, or its email is waiting for its job.

  A member with no email gets `:first` or `:replace` published, and nothing emailed
  (`emailed?/1`). `record` has the member, their current `letter` or nil, the letter's
  `changes`, and `total_minutes`, their hours for the year.
  """
  def what(%{total_minutes: 0}), do: nil
  def what(%{letter: nil}), do: :first
  def what(%{changes: [_ | _]}), do: :replace

  def what(%{letter: letter, member: member}) do
    cond do
      not emailed?(member) -> nil
      letter.email_status == :sending -> nil
      letter.email_status == :failed -> :failed
      letter.email_status == :sent -> :again
      true -> :not_emailed
    end
  end

  @doc "Whether Email publishes the member's letter first."
  def publishes?(what), do: what in [:first, :replace]

  @doc "Whether the member gets the letter by email: they have an email."
  def emailed?(member), do: member.email not in [nil, ""]

  @doc """
  Why `year`'s letters can't be emailed yet, or nil when they can: its year isn't over
  in the team's time zone, so they would need publishing again once it ends.
  """
  def refusal(year, %Team{} = team, now) do
    if TaxCreditLetter.year_over?(year, now, team.timezone),
      do: nil,
      else:
        "#{year} letters can be emailed from #{Service.Format.date_long(Date.new!(year + 1, 1, 1))}."
  end

  @doc """
  Email for one member, from their letter page: publishes their letter first when it
  needs to, then emails it at once with `EmailTaxCreditLetter.send_now/2`, so the page
  says whether it went. `{:ok, %{letter, published, email}}`, where `email` is `:ok`,
  `:no_email`, or `{:error, reason}`, or `{:error, message}` with nothing done.
  """
  def call_one(
        %Team{} = team,
        %Member{} = member,
        year,
        %User{} = user,
        now \\ Service.Clock.utc_now()
      ) do
    case refusal(year, team, now) do
      nil -> email_one(team, %{member | team: team}, year, user, now)
      message -> {:error, message}
    end
  end

  defp email_one(team, member, year, user, now) do
    read = PrintTaxCreditLetter.read(team, member.id, year, now)
    record = record(team, member, year, TaxCreditLetter.get_current(member, year), read, now)

    with {:ok, what} <- offered(record),
         {:ok, letter} <- latest(team, record, what, user.id, now) do
      {:ok, %{letter: letter, published: publishes?(what), email: send_now(letter, member, now)}}
    end
  end

  defp send_now(letter, member, now) do
    if emailed?(member), do: EmailTaxCreditLetter.send_now(letter, now), else: :no_email
  end

  # Why Email isn't offered to the member, said as an error.
  defp offered(record) do
    case what(record) do
      nil -> {:error, not_offered(record)}
      what -> {:ok, what}
    end
  end

  defp not_offered(%{total_minutes: 0, member: member, year: year}),
    do: "#{member.name} has no hours in #{year}, so there is no letter to email."

  defp not_offered(%{letter: %{email_status: :sending}}),
    do: "The letter is being emailed now. Reload to see it."

  defp not_offered(%{member: member}), do: "#{member.name} has no email."

  @doc """
  Email for many members of the team, from the letters list: refuses a year that isn't
  over, else queues the job that emails them. `{:ok, count}` or `{:error, message}`.
  """
  def call(%Team{} = team, year, member_ids, %User{} = user, now \\ Service.Clock.utc_now()) do
    case refusal(year, team, now) do
      nil ->
        EmailTaxCreditLettersWorker.enqueue(team, year, member_ids, user)
        {:ok, length(member_ids)}

      message ->
        {:error, message}
    end
  end

  @doc """
  The job's work: for each of these members of the team, what `what/1` says, in order
  of name. A new letter and its email job commit together, so a retry makes only what's
  still missing. Records the counts as an event, tells the letter list, and returns the
  summary, `%{year, published, emailing, not_emailed, refused, stale}`: `not_emailed` the
  members with no email who got a letter published, and `refused` the messages of those
  a value they need kept from being published, by member.
  """
  def run(%Team{} = team, year, member_ids, user_id, now \\ Service.Clock.utc_now()) do
    summary =
      case refusal(year, team, now) do
        nil ->
          team
          |> records(year, member_ids, now)
          |> Enum.map(&deliver(team, &1, user_id, now))
          |> summarize(year)

        message ->
          %{summarize([], year) | refused: [{nil, message}]}
      end

    record_event(team, user_id, summary)
    Phoenix.PubSub.broadcast(App.PubSub, topic(team.id), {:tax_credit_letters_emailed, summary})
    summary
  end

  # Each member's letter as Email finds it, read at once (PrintTaxCreditLetter.read_each/4).
  defp records(team, year, member_ids, now) do
    members =
      Member
      |> where([m], m.team_id == ^team.id and m.id in ^member_ids)
      |> order_by([m], asc: m.name)
      |> Repo.all()
      |> Enum.map(&%{&1 | team: team})

    ids = Enum.map(members, & &1.id)

    letters =
      team |> TaxCreditLetter.get_all_current_for(ids, year) |> Map.new(&{&1.member_id, &1})

    reads = PrintTaxCreditLetter.read_each(team, ids, year, now)

    for member <- members,
        do: record(team, member, year, letters[member.id], reads[member.id], now)
  end

  # Where the member's letter is: what `what/1` reads, and the read publishing prints from.
  defp record(team, member, year, current, read, now) do
    today = PrintTaxCreditLetter.today(team, read)
    current = current && %{current | member: member}

    %{
      member: member,
      year: year,
      letter: current,
      read: read,
      today: today,
      total_minutes: total_minutes(today),
      changes: changes(current, today, team, now)
    }
  end

  defp changes(nil, _today, _team, _now), do: []

  defp changes(letter, today, team, now),
    do: TaxCreditLetter.changes(letter, today, now, team.timezone)

  defp total_minutes(%{keep: keep}),
    do: (keep["hours.primary"] || 0) + (keep["hours.secondary"] || 0)

  # One member of many: publishes first when it needs to, and queues the email with the
  # letter it goes with.
  defp deliver(team, record, user_id, now) do
    case what(record) do
      nil -> {record.member, :skipped}
      what -> deliver(team, record, what, user_id, now)
    end
  end

  defp deliver(team, record, what, user_id, now) do
    if publishes?(what) do
      {record.member, publish(team, record, user_id, now)}
    else
      {:ok, _letter} = Repo.transaction(fn -> enqueue_email(record.letter) end)
      {record.member, :emailing}
    end
  end

  # A new letter and its email job commit together.
  defp publish(team, record, user_id, now) do
    %{member: member, year: year, read: read} = record

    with {:ok, prepared} <-
           PublishTaxCreditLetter.prepare(team, member.id, year, user_id, now, read),
         {:ok, email} <- Repo.transaction(fn -> publish_and_email(prepared, record) end) do
      {:published, email}
    else
      {:error, :stale} -> :stale
      {:error, {:needed, needed}} -> {:refused, needed_error(member, needed)}
    end
  end

  # What a letter needs, said for the button: Email, or Publish letter with no email.
  defp needed_error(member, needed) do
    verb = if emailed?(member), do: "emailed", else: "published"
    ReadDocument.needed_error("This letter", needed, verb)
  end

  defp publish_and_email(prepared, record) do
    case PublishTaxCreditLetter.insert(prepared, current_id(record)) do
      {:ok, letter} -> email_or_not(letter, record.member)
      {:error, :stale} -> Repo.rollback(:stale)
    end
  end

  defp email_or_not(letter, member) do
    if emailed?(member) do
      enqueue_email(letter)
      :emailing
    else
      :no_email
    end
  end

  defp current_id(%{letter: nil}), do: nil
  defp current_id(%{letter: letter}), do: letter.id

  # The latest letter for one member: a new one when Email publishes, else the current.
  defp latest(team, record, what, user_id, now) do
    %{member: member, year: year, read: read} = record

    with true <- publishes?(what),
         {:ok, prepared} <-
           PublishTaxCreditLetter.prepare(team, member.id, year, user_id, now, read),
         {:ok, letter} <- PublishTaxCreditLetter.insert(prepared, current_id(record)) do
      {:ok, letter}
    else
      false -> {:ok, record.letter}
      {:error, :stale} -> {:error, "Someone just published this letter. Reload to see it."}
      {:error, {:needed, needed}} -> {:error, needed_error(member, needed)}
    end
  end

  defp enqueue_email(letter) do
    letter = TaxCreditLetter.set_email_status!(letter, :sending)
    EmailTaxCreditLetterWorker.enqueue(letter)
    letter
  end

  @doc """
  The summary of `{member, result}` from many: how many were published and emailing,
  who got a letter with no email, and the messages of those refused. Pure.
  """
  def summarize(results, year) do
    %{
      year: year,
      published: Enum.count(results, &match?({_member, {:published, _email}}, &1)),
      emailing: Enum.count(results, &(elem(&1, 1) in [:emailing, {:published, :emailing}])),
      not_emailed: for({member, {:published, :no_email}} <- results, do: member),
      refused: for({member, {:refused, message}} <- results, do: {member, message}),
      stale: Enum.count(results, &(elem(&1, 1) == :stale))
    }
  end

  # Ids and counts only, never names or emails, as Event asks.
  defp record_event(team, user_id, summary) do
    Event.record!(:tax_credit_letters_sent,
      team_id: team.id,
      user_id: user_id,
      data: %{
        year: summary.year,
        published: summary.published,
        emailing: summary.emailing,
        not_emailed_member_ids: Enum.map(summary.not_emailed, & &1.id),
        refused: length(summary.refused)
      }
    )
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

  defp broadcast_emailed(%PublishedPDF{} = letter) do
    Phoenix.PubSub.broadcast(
      App.PubSub,
      topic(letter.member.team_id),
      {:tax_credit_letter_emailed, letter.id}
    )
  end
end
