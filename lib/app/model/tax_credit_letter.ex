defmodule App.Model.TaxCreditLetter do
  @moduledoc """
  A tax credit letter is a published PDF of the definition `Tax credit letter`,
  priv/documents/tax_credit_letter.txt (#918, #970), for a member's year: its subject is
  `member:45:2026`. Its ID, the hours it printed (`keep`), when it was published, its
  member's first download, and its email are on its App.Model.PublishedPDF. Publishing
  again keeps the old one, Replaced, and withdrawing one ends it, so the member lists
  under No letter again. Letters stay their own feature: the hours rule, the letter list
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

  @doc """
  The year whose letters go out now: last year. Letters for it, or for the year
  still under way, warn when attendance no longer adds up to their hours (#192).
  """
  def current_year(now, timezone), do: Service.YearRange.year_in(now, timezone) - 1

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
  How the letter's hours compare with `hours`, today's count from
  `CountTaxCreditHours`:

  - `:unknown`: an old letter with no saved hours.
  - `:same`: they agree.
  - `:changed`: they differ, and the letter is for the current year or later, so it
    may be worth publishing again: it's out of date.
  - `:changed_old`: they differ on an older letter. It stays as it is.
  """
  def hours_status(%PublishedPDF{} = letter, hours, now, timezone) do
    cond do
      minutes(letter) == nil -> :unknown
      minutes(letter) == {hours.primary_minutes, hours.secondary_minutes} -> :same
      letter.year >= current_year(now, timezone) -> :changed
      true -> :changed_old
    end
  end
end
