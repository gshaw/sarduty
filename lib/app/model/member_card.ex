defmodule App.Model.MemberCard do
  use App, :model

  alias App.Field.EncryptedString
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.Organization
  alias App.Model.PassRegistration
  alias App.Model.Team
  alias App.Repo

  # A member's ID card. The code is what a checker types or scans at /verify, so it is
  # random rather than the D4H member number: a guessable code would let anyone walk
  # the roster. A member has at most one card that isn't revoked.
  schema "member_cards" do
    belongs_to :team, Team
    belongs_to :member, Member
    field :code, :string, redact: true
    field :revoked_at, :utc_datetime_usec
    has_many :pass_registrations, PassRegistration
    # Apple Wallet pass updates: Wallet sends the token back to prove it holds the pass,
    # the fingerprint is the pass as last sent, and pass_updated_at is when it changed.
    field :authentication_token, EncryptedString, redact: true
    field :pass_fingerprint, :string
    field :pass_updated_at, :utc_datetime_usec
    # When a phone last fetched the pass, and when a manager last sent a test update.
    field :pass_fetched_at, :utc_datetime_usec
    # Shared by a member's cards, so a replacement updates the same Wallet pass.
    field :serial_number, :string
    # Google Wallet: the pass as last sent to Google, or nil when it has none.
    field :google_pass_fingerprint, :string
    # When the member said the card is in Wallet, for "For you to do" (#389). Apple
    # Wallet tells SAR Duty itself, through pass_registrations.
    field :in_wallet_at, :utc_datetime_usec
    # Whether its email went (#893): sending while its job waits, then sent or failed.
    # Empty for a card never emailed, or one made before.
    field :email_status, Ecto.Enum, values: [:sending, :sent, :failed]
    field :emailed_at, :utc_datetime_usec
    # When its passes expire, as last built: rolls with valid_until/1 while the card is
    # active, and stays put once it isn't, so Wallet shows the pass expired (#893).
    field :expires_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  # cspell:ignore ABCDEFGHJKMNPQRSTVWXYZ -- the code alphabet
  # No 0/O, 1/I/L, or U, so a code read off a phone or typed from a photo survives.
  # 30 characters, 8 long: about 6.6 × 10^11 codes.
  @alphabet ~c"23456789ABCDEFGHJKMNPQRSTVWXYZ"
  @code_length 8

  # Coast Range SAR's sample cards (App.CoastRange, #854) start with it, and no real card does.
  @sample_prefix "SAMP"

  @doc "A new random code, stored without the dash: `K7Q4M2XA`. Never a sample's."
  def generate_code do
    code = random_chars(@code_length, "")
    if sample_code?(code), do: generate_code(), else: code
  end

  @doc "Whether a stored code is one of Coast Range SAR's sample cards, made up for demos."
  def sample_code?(code), do: String.starts_with?(code, @sample_prefix)

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
  Each member's live card on the team, for reports: `member_id`, `code` as printed (the
  SQL twin of `format_code/1`), and `issued_at`.
  """
  def live_query(%Team{} = team) do
    half = div(@code_length, 2)

    from(c in MemberCard,
      where: c.team_id == ^team.id and is_nil(c.revoked_at),
      select: %{
        member_id: c.member_id,
        code:
          fragment("substr(?, 1, ?) || '-' || substr(?, ?)", c.code, ^half, c.code, ^(half + 1)),
        issued_at: c.inserted_at
      }
    )
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

  @doc "How to verify a card, for the back of the pass. `code` is as printed."
  def how_to_check(code) do
    "Scan the QR code with a phone's camera. The page it opens must be verify.sarduty.com, " <>
      "and the photo must match the person. Or open verify.sarduty.com and enter #{code}."
  end

  @doc """
  Who issued the card, for the back of the pass. A team in an organization names it
  instead of SAR Duty. Expects the team with `:organization` preloaded.
  """
  def issued_by(%Team{organization: %Organization{name: organization}} = team),
    do:
      "#{team.legal_name}, a member team of #{organization}. Status comes from the team's records."

  def issued_by(%Team{organization: nil} = team),
    do: "#{team.legal_name} through SAR Duty. Status comes from the team's records."

  @doc """
  The code in what a scanner read: a bare code, or a link to a card's page,
  `/K7Q4-M2XA`, on one of `hosts`. `{:other_site, host}` for a link anywhere else, which
  is what a forged card would carry. Nil when it's neither.
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
    case Regex.run(~r{^/([^/]+)/?$}, path || "") do
      [_, code] -> normalize_code(code)
      nil -> nil
    end
  end

  @doc """
  `:active` while the member is in good standing (Member.good_standing?/3: current and
  not retiring), `:inactive` once they aren't, or `:revoked` for a replaced card or one
  the team's ID cards switch cancelled. A member who comes back gets the same card back,
  active. `repo` is App.SampleRepo for a sample card.
  """
  def status(card, now, repo \\ Repo)

  def status(%MemberCard{revoked_at: nil, member: member}, now, repo) do
    if Member.good_standing?(member, now, repo), do: :active, else: :inactive
  end

  def status(%MemberCard{}, _now, _repo), do: :revoked

  @doc """
  What a card's link (#952) offers: `:active`, its passes; or why not: `:replaced`, a
  revoked card whose member has a newer live one; `:cancelled`, a revoked card with none,
  as when the team's ID cards were turned off; `:inactive`, a member not in good
  standing. Expects `member: :team`.
  """
  def link_status(%MemberCard{} = card, now) do
    case status(card, now) do
      :revoked -> if find_current(card.member.team, card.member), do: :replaced, else: :cancelled
      status -> status
    end
  end

  @doc """
  A card by id, with `member: [team: :organization]`, or nil. Its member is found
  through the card's team.
  """
  def get_with_member(id) do
    MemberCard
    |> join(:inner, [c], m in assoc(c, :member), on: m.team_id == c.team_id)
    |> where([c], c.id == ^id)
    |> preload(member: [team: :organization])
    |> Repo.one()
  end

  @doc "A revoked card, by id, or nil. Its member is found through the card's team."
  def get_revoked(id) do
    MemberCard
    |> join(:inner, [c], m in assoc(c, :member), on: m.team_id == c.team_id)
    |> where([c], c.id == ^id and not is_nil(c.revoked_at))
    |> Repo.one()
  end

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

  @doc """
  Pure. When the card's passes expire, given its `status`: valid_until/1 while active,
  so it rolls with each refresh, and the date it last had once it isn't, so a former
  member's pass shows expired within three months. Expects `member: :team`.
  """
  def expires_at(%MemberCard{member: %{team: team}}, :active), do: valid_until(team)
  def expires_at(%MemberCard{expires_at: %DateTime{} = expires_at}, _status), do: expires_at
  def expires_at(%MemberCard{member: %{team: team}}, _status), do: valid_until(team)

  @doc "Stores expires_at/2 on the card when it moved, before a pass is built."
  def record_expires_at!(%MemberCard{} = card, status) do
    expires_at = expires_at(card, status)

    if same_time?(expires_at, card.expires_at),
      do: card,
      else: card |> change(expires_at: usec(expires_at)) |> Repo.update!()
  end

  defp usec(nil), do: nil
  defp usec(%DateTime{} = time), do: DateTime.add(time, 0, :microsecond)

  # A stored time comes back with microseconds, so == would see every one as moved.
  defp same_time?(nil, nil), do: true
  defp same_time?(%DateTime{} = a, %DateTime{} = b), do: DateTime.compare(a, b) == :eq
  defp same_time?(_a, _b), do: false

  @doc "Records how the card's email went: `:sending` when its job is queued, then the result."
  def set_email_status!(%MemberCard{} = card, :sent, now),
    do: card |> change(email_status: :sent, emailed_at: now) |> Repo.update!()

  def set_email_status!(%MemberCard{} = card, status, _now),
    do: card |> change(email_status: status) |> Repo.update!()

  def find_by_code(code, repo \\ Repo) do
    MemberCard
    |> where([c], c.code == ^code)
    |> preload(member: [team: :organization])
    |> repo.one()
  end

  def find_current(%Team{} = team, %Member{} = member) do
    MemberCard
    |> where([c], c.team_id == ^team.id and c.member_id == ^member.id and is_nil(c.revoked_at))
    |> Repo.one()
  end

  def insert!(%MemberCard{} = card), do: Repo.insert!(card)

  @doc "A secret for the pass web service, 32 random bytes as hex."
  def generate_authentication_token, do: Service.Random.hex(32)

  @doc "Revokes every live card on the team and returns them."
  def revoke_team!(%Team{} = team, now) do
    {_count, cards} =
      MemberCard
      |> where([c], c.team_id == ^team.id and is_nil(c.revoked_at))
      |> select([c], c)
      |> Repo.update_all(set: [revoked_at: now, updated_at: now, pass_updated_at: now])

    cards
  end

  def count_live_by_team do
    MemberCard
    |> where([c], is_nil(c.revoked_at))
    |> group_by([c], c.team_id)
    |> select([c], {c.team_id, count(c.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Revokes the member's live cards and returns them, when a card replaces them."
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
    |> preload(member: [team: :organization])
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

  @doc """
  The PubSub topic a member's card pages listen on: `:pass_fetched` when a phone fetches
  the pass, `:wallet_changed` when a phone registers or drops it or Google says it was
  saved or deleted (#952), and `:card_changed` for a new card or its email.
  """
  def pass_topic(member_id), do: "member_card:#{member_id}"

  @doc "Tells the member's card pages that what SAR Duty knows of their Wallets changed."
  def broadcast_wallet_changed(member_id),
    do: Phoenix.PubSub.broadcast(App.PubSub, pass_topic(member_id), :wallet_changed)

  def record_google_pass!(%MemberCard{} = card, fingerprint) do
    card |> change(google_pass_fingerprint: fingerprint) |> Repo.update!()
  end

  @doc "The team's live cards that have a Google Wallet pass."
  def get_all_on_google(%Team{} = team) do
    MemberCard
    |> where([c], c.team_id == ^team.id and is_nil(c.revoked_at))
    |> where([c], not is_nil(c.google_pass_fingerprint))
    |> preload(member: [team: :organization])
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
    |> preload(member: [team: :organization])
    |> Repo.all()
  end

  @doc """
  Whether the card is in a Wallet, as far as SAR Duty knows: a phone registered its Apple
  Wallet pass, or the card was marked in Wallet. An Apple replacement lands on the same
  pass, so its serial counts; a Google replacement is a new pass, so only the card's own
  mark does.
  """
  def in_wallet?(%MemberCard{in_wallet_at: %DateTime{}}), do: true
  def in_wallet?(%MemberCard{} = card), do: PassRegistration.get_all_for_serial(card) != []

  def mark_in_wallet!(%MemberCard{} = card, now) do
    card = card |> change(in_wallet_at: now) |> Repo.update!()
    broadcast_wallet_changed(card.member_id)
    card
  end

  def mark_out_of_wallet!(%MemberCard{} = card) do
    card = card |> change(in_wallet_at: nil) |> Repo.update!()
    broadcast_wallet_changed(card.member_id)
    card
  end
end
