defmodule App.Model.TaxCreditLetter do
  @moduledoc """
  A tax credit letter is a published PDF of the definition `Tax credit letter`,
  priv/documents/tax_credit_letter.txt (#918, #970), for a member's year: its subject is
  `member:45:2026`. Its ID, the hours it printed (`keep`), when it was published, and
  its email are on its App.Model.PublishedPDF. Publishing again keeps the old one,
  Replaced, and withdrawing one ends it, so the member lists under No letter again. Letters stay their own feature: the hours rule, the letter list
  with Send letters, and the settings tab are code; this module is the queries and rules
  that are only theirs.
  """
  import Ecto.Query

  alias App.Model.Member
  alias App.Model.PublishedPDF
  alias App.Model.Team
  alias App.Repo

  @name "Tax credit letter"

  @doc "The letter definition's name, which every letter's PDF has."
  def name, do: @name

  @doc "A member's year, which a letter is for: `member:45:2026`."
  def subject(member_id, year), do: "member:#{member_id}:#{year}"

  @doc "The team's letters, current or not."
  def query(team_id), do: where(PublishedPDF, [p], p.team_id == ^team_id and p.name == @name)

  @doc "The current letters among `query`: neither replaced nor withdrawn."
  def current(query),
    do: where(query, [p], is_nil(p.replaced_by_id) and is_nil(p.withdrawn_at))

  @doc "The team's letter `id`, current or not, with its member and team. Raises when not."
  def find!(%Team{id: team_id}, id) do
    team_id |> query() |> where([p], p.id == ^id) |> preload(member: :team) |> Repo.one!()
  end

  @doc "A current letter of this member's, by id, for the member's own page (#156). Raises when not."
  def find_for_member!(%Member{} = member, id) do
    member.team_id
    |> query()
    |> current()
    |> where([p], p.id == ^id and p.member_id == ^member.id)
    |> preload(member: :team)
    |> Repo.one!()
  end

  @doc "The member's current letters, newest year first."
  def get_all_for_member(%Member{} = member) do
    member.team_id
    |> query()
    |> current()
    |> where([p], p.member_id == ^member.id)
    |> order_by([p], desc: p.year, desc: p.inserted_at)
    |> Repo.all()
  end

  @doc "The member's current letter for `year`, or nil."
  def get_current(%Member{} = member, year) do
    member.team_id
    |> query()
    |> current()
    |> where([p], p.member_id == ^member.id and p.year == ^year)
    |> Repo.one()
  end

  @doc "The team's current letters among `ids`, with their members and team, as the list checks them."
  def get_all_current(%Team{id: team_id}, ids) do
    team_id
    |> query()
    |> current()
    |> where([p], p.id in ^ids)
    |> preload(member: :team)
    |> Repo.all()
  end

  @doc "The members on the team with a current letter for `year`."
  def member_ids(team_id, year) do
    team_id
    |> query()
    |> current()
    |> where(year: ^year)
    |> select([p], p.member_id)
    |> Repo.all()
  end

  @doc """
  A current letter whose email is waiting for its job, with its member and team, or nil
  once it's sent, failed, replaced, withdrawn, or gone.
  """
  def get_sending(id) do
    PublishedPDF
    |> where([p], p.id == ^id and p.name == @name and p.email_status == :sending)
    |> current()
    |> preload(member: :team)
    |> Repo.one()
  end

  @doc "Records how the letter's email went."
  def set_email_status!(%PublishedPDF{} = letter, status),
    do: letter |> Ecto.Changeset.change(email_status: status) |> Repo.update!()

  @doc "Records that the letter's email went at `now`."
  def set_emailed!(%PublishedPDF{} = letter, now) do
    letter
    |> Ecto.Changeset.change(
      email_status: :sent,
      emailed_at: DateTime.truncate(now, :microsecond)
    )
    |> Repo.update!()
  end

  @doc """
  Where the letter's email is, for the list's Letter column and the letter page:
  `:emailed`, `:sending` while its job waits, `:failed` when the send was refused,
  `:no_email` when its member has no email, else `:not_emailed`.
  """
  def email_state(%PublishedPDF{email_status: :sent}, _member), do: :emailed
  def email_state(%PublishedPDF{email_status: :sending}, _member), do: :sending

  def email_state(%PublishedPDF{email_status: status}, member) do
    cond do
      member.email in [nil, ""] -> :no_email
      status == :failed -> :failed
      true -> :not_emailed
    end
  end

  @doc """
  The year whose letters go out now: last year. Its letters, and those for the year
  still under way, can go out of date; older years' are closed (`closed?/3`).
  """
  def current_year(now, timezone), do: Service.YearRange.year_in(now, timezone) - 1

  @doc """
  Whether `year`'s letters are closed: older than last year. A member may have filed
  one, so it stays as published and never goes out of date (#192, #995).
  """
  def closed?(year, now, timezone), do: year < current_year(now, timezone)

  @doc "The minutes the letter printed, `{primary, secondary}`, or nil for one that kept none."
  def minutes(%PublishedPDF{keep: keep}) do
    case {keep["hours.primary"], keep["hours.secondary"]} do
      {primary, secondary} when is_integer(primary) and is_integer(secondary) ->
        {primary, secondary}

      _missing ->
        nil
    end
  end

  @doc "The letter's total minutes, or nil."
  def total_minutes(letter) do
    case minutes(letter) do
      {primary, secondary} -> primary + secondary
      nil -> nil
    end
  end

  @doc """
  What reads differently on the letter's verify page today, as for every published PDF
  (PublishedPDF.changes/2), from `today`, PrintTaxCreditLetter.today/2's: `[]` when
  nothing does, and always for a closed year's letter. A line here makes it out of date.
  """
  def changes(%PublishedPDF{} = letter, today, now, timezone) do
    if closed?(letter.year, now, timezone), do: [], else: PublishedPDF.changes(letter, today)
  end
end
