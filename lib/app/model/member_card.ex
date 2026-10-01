defmodule App.Model.MemberCard do
  use App, :model

  alias App.Field.EncryptedString
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.PassRegistration
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
    has_many :pass_registrations, PassRegistration
    # Apple Wallet pass updates: Wallet sends the token back to prove it holds the pass,
    # the fingerprint is the pass as last sent, and pass_updated_at is when it changed.
    field :authentication_token, EncryptedString, redact: true
    field :pass_fingerprint, :string
    field :pass_updated_at, :utc_datetime_usec
    # When a phone last fetched the pass, and when a manager last sent a test update.
    field :pass_fetched_at, :utc_datetime_usec
    field :pass_test_at, :utc_datetime_usec
    # Shared by a member's cards, so a replacement updates the same Wallet pass.
    field :serial_number, :string
    # Google Wallet: the pass as last sent to Google, or nil when it has none.
    field :google_pass_fingerprint, :string
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

  @doc """
  What the card's QR code holds: its page on the verify site, so a phone's camera opens
  the check. In capitals, because a QR code packs capitals, digits, and `:/.-` into fewer
  squares, and neither the host nor the code cares about case.
  `HTTPS://VERIFY.SARDUTY.COM/K7Q4-M2XA`.
  """
  def qr_url(code, verify_url), do: String.upcase("#{verify_url}/#{format_code(code)}")

  @doc "How to check a card, for the back of the pass. `code` is as printed."
  def how_to_check(code) do
    "Scan the QR code with your phone's camera. Check that the page it opens is " <>
      "verify.sarduty.com, and that the photo matches the person. Or open " <>
      "verify.sarduty.com and type #{code}."
  end

  @doc """
  The code in what a scanner read: a bare code, as on the first cards, or a link to a
  card's page on one of `hosts`: `/K7Q4-M2XA` on the verify site, or `/verify/K7Q4-M2XA`
  on the app's host, as cards linked before the verify site. `{:other_site, host}` for a
  link anywhere else, which is what a forged card would carry. Nil when it's neither.
  """
  def code_from_scan(text, hosts) when is_binary(text) do
    case text |> String.trim() |> URI.parse() do
      %URI{scheme: scheme, host: link_host, path: path}
      when scheme in ["http", "https", "HTTP", "HTTPS"] and is_binary(link_host) ->
        link_host = String.downcase(link_host)

        if link_host in Enum.map(hosts, &String.downcase/1),
          do: code_from_path(path),
          else: {:other_site, link_host}

      _ ->
        normalize_code(text)
    end
  end

  defp code_from_path(path) do
    case Regex.run(~r{^(?:/verify)?/([^/]+)/?$}i, path || "") do
      [_, code] -> normalize_code(code)
      nil -> nil
    end
  end

  @doc "`:active`, `:inactive` when the member has left the team, or `:revoked`."
  def status(%MemberCard{revoked_at: nil, member: member}, now) do
    if Member.current?(member, now), do: :active, else: :inactive
  end

  def status(%MemberCard{}, _now), do: :revoked

  @doc """
  When a pass stops being good: the last moment of the month three months after the
  team last checked D4H, in the team's zone. Each refresh moves it, so a pass expires on
  its own once updates stop. Nil when the team has never refreshed.
  """
  def valid_until(%Team{d4h_refreshed_at: nil}), do: nil

  def valid_until(%Team{d4h_refreshed_at: refreshed_at, timezone: timezone}) do
    refreshed_at
    |> DateTime.shift_zone!(timezone)
    |> DateTime.to_date()
    |> Date.shift(month: 3)
    |> Date.end_of_month()
    |> DateTime.new!(~T[23:59:59], timezone)
    |> DateTime.shift_zone!("Etc/UTC")
  end

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

  @doc "A secret for the pass web service, 32 random bytes as hex."
  def generate_authentication_token, do: Service.Random.hex(32)

  @doc "Revokes the member's live cards and returns them."
  def revoke_all!(%Team{} = team, %Member{} = member, now) do
    {_count, cards} =
      MemberCard
      |> where([c], c.team_id == ^team.id and c.member_id == ^member.id and is_nil(c.revoked_at))
      |> select([c], c)
      |> Repo.update_all(set: [revoked_at: now, updated_at: now, pass_updated_at: now])

    cards
  end

  @doc """
  The card behind a Wallet request: the member's cards share a serial number, and the
  token says which one the phone holds. A phone with a replaced card's pass only ever
  gets that card, voided.
  """
  def find_by_serial_number_and_token(serial_number, token) when is_binary(token) do
    MemberCard
    |> where([c], c.serial_number == ^serial_number)
    |> preload(member: :team)
    |> Repo.all()
    |> Enum.find(
      &(is_binary(&1.authentication_token) and
          Plug.Crypto.secure_compare(&1.authentication_token, token))
    )
  end

  def find_by_serial_number_and_token(_serial_number, _token), do: nil

  def serial_number(%MemberCard{serial_number: serial_number}), do: serial_number

  @doc "A new card takes the serial of the member's last card, so Wallet updates that pass."
  def next_serial_number(%Team{} = team, %Member{} = member) do
    MemberCard
    |> where([c], c.team_id == ^team.id and c.member_id == ^member.id)
    |> order_by([c], desc: c.id)
    |> limit(1)
    |> select([c], c.serial_number)
    |> Repo.one()
    |> Kernel.||("member-#{member.id}")
  end

  def ensure_authentication_token!(%MemberCard{authentication_token: nil} = card) do
    card
    |> change(authentication_token: generate_authentication_token())
    |> Repo.update!()
  end

  def ensure_authentication_token!(card), do: card

  def record_pass!(%MemberCard{} = card, fingerprint, now) do
    changes =
      if card.pass_fingerprint == fingerprint,
        do: [pass_fingerprint: fingerprint],
        else: [pass_fingerprint: fingerprint, pass_updated_at: now]

    card |> change(changes) |> Repo.update!()
  end

  @doc "Records that a phone fetched the pass, and tells the member's ID Card tab."
  def record_pass_fetched!(%MemberCard{} = card, now) do
    card = card |> change(pass_fetched_at: now) |> Repo.update!()
    Phoenix.PubSub.broadcast(App.PubSub, pass_topic(card.member_id), :pass_fetched)
    card
  end

  @doc "The PubSub topic a member's ID Card tab listens on for phone fetches."
  def pass_topic(member_id), do: "member_card:#{member_id}"

  @doc """
  Marks a test update. Bumping `pass_updated_at` makes the phone see the pass as
  changed when it asks; the fingerprint is left alone, so a refresh doesn't push it.
  """
  def record_test_update!(%MemberCard{} = card, now) do
    card |> change(pass_test_at: now, pass_updated_at: now) |> Repo.update!()
  end

  def record_google_pass!(%MemberCard{} = card, fingerprint) do
    card |> change(google_pass_fingerprint: fingerprint) |> Repo.update!()
  end

  @doc "The team's live cards that have a Google Wallet pass."
  def get_all_on_google(%Team{} = team) do
    MemberCard
    |> where([c], c.team_id == ^team.id and is_nil(c.revoked_at))
    |> where([c], not is_nil(c.google_pass_fingerprint))
    |> preload(member: :team)
    |> Repo.all()
  end

  @doc "The team's live cards whose Wallet serial at least one phone is registered for."
  def get_all_registered(%Team{} = team) do
    registered_serials =
      PassRegistration
      |> join(:inner, [r], c in MemberCard, on: c.id == r.member_card_id)
      |> select([r, c], c.serial_number)

    MemberCard
    |> where([c], c.team_id == ^team.id and is_nil(c.revoked_at))
    |> where([c], c.serial_number in subquery(registered_serials))
    |> preload(member: :team)
    |> Repo.all()
  end
end
