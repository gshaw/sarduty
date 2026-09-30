defmodule App.Model.MemberCard do
  use App, :model

  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.Team
  alias App.Repo

  # A member's ID card. The code is what a checker types or scans at /verify, so it is
  # random rather than the D4H member number: a guessable code would let anyone walk
  # the roster. A member has at most one card that isn't revoked.
  schema "member_cards" do
    belongs_to :team, Team
    belongs_to :member, Member
    field :code, :string
    field :revoked_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  # cspell:ignore ABCDEFGHJKMNPQRSTVWXYZ -- the code alphabet
  # No 0/O, 1/I/L, or U, so a code read off a phone or typed from a photo survives.
  # 30 characters, 8 long: about 6.6 × 10^11 codes.
  @alphabet ~c"23456789ABCDEFGHJKMNPQRSTVWXYZ"
  @code_length 8

  @doc "A new random code, stored without the dash: `K7Q4M2XA`."
  def generate_code, do: random_chars(@code_length, "")

  defp random_chars(0, acc), do: acc

  # Bytes of 240 and up are skipped so each character is equally likely.
  defp random_chars(n, acc) do
    case :crypto.strong_rand_bytes(1) do
      <<byte>> when byte < 240 ->
        random_chars(n - 1, acc <> <<Enum.at(@alphabet, rem(byte, length(@alphabet)))>>)

      _ ->
        random_chars(n, acc)
    end
  end

  @doc "The code as printed on the card: `K7Q4-M2XA`."
  def format_code(code) do
    {first, last} = String.split_at(code, div(@code_length, 2))
    "#{first}-#{last}"
  end

  @doc """
  What someone typed or scanned, reduced to a stored code, or nil when it can't be one.
  Case, spaces and dashes don't matter.
  """
  def normalize_code(input) when is_binary(input) do
    code = input |> String.upcase() |> String.replace(~r/[\s-]/, "")

    chars = String.to_charlist(code)
    if length(chars) == @code_length and Enum.all?(chars, &(&1 in @alphabet)), do: code
  end

  def normalize_code(_input), do: nil

  @doc "`:active`, `:inactive` when the member has left the team, or `:revoked`."
  def status(%MemberCard{revoked_at: nil, member: member}, now) do
    if Member.current?(member, now), do: :active, else: :inactive
  end

  def status(%MemberCard{}, _now), do: :revoked

  def find_by_code(code) do
    MemberCard
    |> where([c], c.code == ^code)
    |> preload(member: :team)
    |> Repo.one()
  end

  def find_current(%Team{} = team, %Member{} = member) do
    MemberCard
    |> where([c], c.team_id == ^team.id and c.member_id == ^member.id and is_nil(c.revoked_at))
    |> Repo.one()
  end

  def insert!(%MemberCard{} = card), do: Repo.insert!(card)

  def revoke_all!(%Team{} = team, %Member{} = member, now) do
    MemberCard
    |> where([c], c.team_id == ^team.id and c.member_id == ^member.id and is_nil(c.revoked_at))
    |> Repo.update_all(set: [revoked_at: now, updated_at: now])
  end
end
