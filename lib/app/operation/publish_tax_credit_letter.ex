defmodule App.Operation.PublishTaxCreditLetter do
  @moduledoc """
  Publishes a member's tax credit letter for a year (#918, #970): prints it from its
  document (App.Operation.PrintTaxCreditLetter) with a new ID and its verify code, and
  saves it as a published PDF (App.Model.PublishedPDF). A first letter and a new one in
  place of one out of date are both this; the member's current letter, if any, becomes
  Replaced. It is not emailed here. It refuses while a value the letter `needs` is blank
  (#995), such as the signer's signature. Printing happens before the write, since Typst
  takes a while and a transaction holds SQLite's one write lock.
  """

  alias App.Accounts.User
  alias App.Model.Member
  alias App.Model.PublishedPDF
  alias App.Model.TaxCreditLetter
  alias App.Model.Team
  alias App.Operation.PrintTaxCreditLetter
  alias App.Operation.ReadDocument

  @doc """
  `{:ok, letter}`, with its member and team, or `{:error, message}` with nothing saved.
  `current_id` is the member's current letter's id the person saw, nil for none.
  """
  def call(%Team{} = team, member_id, year, %User{} = user, current_id, now \\ DateTime.utc_now()) do
    case prepare(team, member_id, year, user.id, now) do
      {:ok, prepared} -> insert_or_stale(prepared, current_id)
      {:error, {:needed, needed}} -> {:error, ReadDocument.needed_error("This letter", needed)}
    end
  end

  defp insert_or_stale(prepared, current_id) do
    case insert(prepared, current_id) do
      {:ok, letter} -> {:ok, letter}
      {:error, :stale} -> {:error, "Someone just published this letter. Reload to see it."}
    end
  end

  @doc """
  The letter printed, and nothing written yet: `{:ok, %{attrs, printed, member}}`, or
  `{:error, {:needed, needed}}` while a value it needs is blank, with nothing printed:
  the caller words it for its button (ReadDocument.needed_error/3). A print that
  fails raises, so no letter is made without its PDF. `user_id` is who publishes it, nil
  for none. `read` is the member's letter as PrintTaxCreditLetter.read/4 read it, when
  the caller has it.
  """
  def prepare(%Team{} = team, member_id, year, user_id, now \\ DateTime.utc_now(), read \\ nil) do
    member = Member.get_by(id: member_id, team_id: team.id)
    read = read || PrintTaxCreditLetter.read(team, member.id, year, now)

    case PrintTaxCreditLetter.needed(read) do
      [] -> {:ok, print(team, member, year, user_id, read)}
      needed -> {:error, {:needed, needed}}
    end
  end

  defp print(team, member, year, user_id, read) do
    code = PublishedPDF.generate_code()

    printed =
      case PrintTaxCreditLetter.call(team, read, code) do
        {:ok, printed} -> printed
        {:error, reason} -> raise "Tax credit letter for #{year} didn't print: #{reason}"
      end

    attrs = %{
      team_id: team.id,
      name: printed.name,
      subject: TaxCreditLetter.subject(member.id, year),
      code: code,
      member_id: member.id,
      year: year,
      user_id: user_id
    }

    %{attrs: attrs, printed: printed, member: %{member | team: team}}
  end

  @doc """
  Saves what `prepare/6` printed: `{:ok, letter}` with its member and team, or
  `{:error, :stale}`. Call it inside the caller's transaction when it writes more.
  """
  def insert(%{attrs: attrs, printed: printed, member: member}, current_id) do
    with {:ok, letter} <- PublishedPDF.publish(attrs, printed, current_id),
         do: {:ok, %{letter | member: member}}
  end

  @doc "Like `insert/2`, raising when another took the letter's place meanwhile."
  def insert!(prepared, current_id) do
    {:ok, letter} = insert(prepared, current_id)
    letter
  end
end
