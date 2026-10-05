# cspell:ignore Exqlite phash southfrasersar -- the SQLite driver, the Erlang hash, SFSAR's subdomain
# Turns a production snapshot into a dev database with personal data replaced by
# realistic fakes. Run with `mise run sanitize <backup>`, where <backup> is a
# data_backup_*.tar.gz.age from backup.sh (needs AGE_IDENTITY, the path to the backup
# identity file) or a plain .db file. Writes db/sarduty_dev.db, keeping the old one
# beside it. No network, no AI: the same snapshot gives the same fakes every run.
#
# Admins, and members who share an email or a name with an admin's member row, stay
# real. Teams in @keep_teams keep their name. Everything else that identifies a person
# is replaced, and a final scan refuses to write the result if any real name, email,
# phone, or address is left.

defmodule Sanitize do
  @keep_teams ["southfrasersar"]

  # cspell:disable -- made-up names and places, not words
  @first_names ~w(Aiden Alexis Amara Ben Blake Carmen Chloe Colin Dana Declan Elena Ethan
    Fiona Gavin Grace Hannah Harjit Ian Isla Jasmine Jordan Kai Keira Liam Lucas Maya
    Megan Mei Nadia Noah Owen Paige Priya Quinn Rachel Riley Ryan Sanjay Sara Sean Simran
    Tara Tessa Theo Victor Wes Wyatt Yuki Zoe Avery Morgan Rowan Logan Nolan Ivy Ella)
  @last_names ~w(Abbott Bains Barnes Bishop Brooks Campbell Chan Chen Clarke Dawson Dhaliwal
    Doyle Ellis Fraser Gill Grant Hayes Henderson Ito Jensen Kaur Kim Lam Larsen MacLeod
    McKay Mercer Morrison Nguyen Novak Olsen Park Patel Pearson Quinlan Reid Ross Sandhu
    Sato Schmidt Sinclair Stewart Tanaka Thompson Tran Walsh Wong Young Zhang Lindqvist
    Okafor Rasmussen Thibault Gauthier Haddad)
  @places [
    "Cedar Ridge",
    "Elk Hollow",
    "Raven Bay",
    "Stony Point",
    "Willow Flats",
    "Bear Pass",
    "Silver Inlet",
    "Fir Hollow",
    "Otter Point",
    "Eagle Bluff",
    "Lynx Ridge",
    "Heron Bay",
    "Copper Canyon",
    "Spruce Hill",
    "Glacier Gap",
    "Cougar Creek",
    "Misty Shore",
    "Timber Bend",
    "Kestrel Lake",
    "Larch Valley",
    "Osprey Point",
    "Quartz Hill",
    "Marten Falls",
    "Hemlock Cove",
    "Bighorn Flats",
    "Juniper Bluff",
    "Coldwater Gap",
    "Tamarack Lake",
    "Wolf Sound",
    "Ptarmigan Ridge"
  ]
  # cspell:enable
  @streets ~w(Cedar Maple Birch Alder Spruce Hemlock Willow Aspen Poplar Laurel Elm Oak
    Fir Pine Juniper Arbutus Dogwood Holly Ridge Lakeview Mountain River Valley Park)
  @street_kinds ~w(Street Avenue Road Drive Crescent Place Way Court Lane)
  @team_suffixes [
    "Ground Search and Rescue",
    "Search and Rescue",
    "Search & Rescue",
    "GSAR",
    "SAR",
    "Rescue",
    "Board"
  ]
  @area_codes %{"BC" => "604", "AB" => "403", "ON" => "416", "NB" => "506", "NS" => "902"}
  @incident_titles [
    "Overdue hiker",
    "Injured hiker on trail",
    "Lost snowshoers",
    "Stranded climbers",
    "Missing person search",
    "Injured mountain biker",
    "Overdue skiers in backcountry",
    "Swiftwater rescue",
    "Lost hunter",
    "Medical call on trail",
    "Night search for lost youth",
    "Evidence search assist",
    "Fallen hiker in gully",
    "Stranded boaters"
  ]

  def run([input | rest]) do
    output = List.first(rest) || "db/sarduty_dev.db"
    tmp = Path.join(System.tmp_dir!(), "sarduty-sanitize-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)

    try do
      db = extract(input, tmp)
      {:ok, _} = App.Vault.start_link([])
      {:ok, conn} = Exqlite.Sqlite3.open(db)
      sanitize(conn)
      :ok = Exqlite.Sqlite3.execute(conn, "VACUUM")
      :ok = Exqlite.Sqlite3.close(conn)
      install(db, output)
    after
      File.rm_rf!(tmp)
    end
  end

  def run(_args) do
    IO.puts("Usage: mise run sanitize <data_backup_*.tar.gz.age | file.db> [output.db]")
    System.halt(1)
  end

  defp extract(input, tmp) do
    db = Path.join(tmp, "prod.db")

    if String.ends_with?(input, ".age") do
      identity =
        System.get_env("AGE_IDENTITY") || raise "Set AGE_IDENTITY to the backup identity file."

      cmd = "age -d -i #{q(identity)} #{q(input)} | tar xz -C #{q(tmp)} tmp/backup.db"
      {_, 0} = System.cmd("sh", ["-c", cmd], into: IO.stream())
      File.rename!(Path.join(tmp, "tmp/backup.db"), db)
    else
      File.cp!(input, db)
    end

    db
  end

  defp q(path), do: "'" <> String.replace(path, "'", "'\\''") <> "'"

  defp install(db, output) do
    if File.exists?(output) do
      {busy, _} = System.cmd("lsof", [output], stderr_to_stdout: true)
      if busy != "", do: raise("#{output} is open. Stop the dev server first.")
      stamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d-%H%M")
      backup = String.replace_suffix(output, ".db", ".before-sanitize-#{stamp}.db")
      File.rename!(output, backup)
      IO.puts("Kept the old database at #{backup}")
    end

    for suffix <- ["-wal", "-shm"], do: File.rm(output <> suffix)
    File.cp!(db, output)
    IO.puts("Wrote #{output}")
  end

  # ---- The sanitizing

  defp sanitize(conn) do
    exec(conn, "BEGIN")

    admins = rows(conn, "SELECT lower(email) FROM users WHERE is_admin") |> Enum.map(&hd/1)
    members = rows(conn, "SELECT id, team_id, name, email, phone, address FROM members")

    teams =
      rows(conn, "SELECT id, name, subdomain, mailing_address, authorized_by_name FROM teams")

    kept_names =
      for [_, _, name, email | _] <- members,
          email && String.downcase(email) in admins,
          into: MapSet.new(),
          do: name

    kept? = fn [_, _, name, email | _] ->
      (email && String.downcase(email) in admins) || MapSet.member?(kept_names, name)
    end

    teams = fake_teams(teams, kept_names)
    team_by_id = Map.new(teams, &{&1.id, &1})
    people = fake_people(members, kept?, team_by_id)
    emails = fake_emails(conn, people, admins)

    replacements = replacements(people, teams, emails)
    scrub = fn text -> scrub(text, replacements) end

    for p <- people, not p.kept? do
      exec(conn, "UPDATE members SET name = ?, email = ?, phone = ?, address = ? WHERE id = ?", [
        p.fake_name,
        p.email && Map.fetch!(emails, String.downcase(p.email)),
        p.fake_phone,
        p.fake_address,
        p.id
      ])
    end

    for [id, position, ref_id] <- rows(conn, "SELECT id, position, ref_id FROM members") do
      exec(conn, "UPDATE members SET position = ?, ref_id = ? WHERE id = ?", [
        scrub.(position),
        scrub.(ref_id),
        id
      ])
    end

    for t <- teams do
      exec(
        conn,
        """
        UPDATE teams SET name = ?, subdomain = ?, mailing_address = ?, authorized_by_name = ?,
          d4h_access_key = NULL, d4h_refresh_result = NULL WHERE id = ?
        """,
        [t.fake_name, t.fake_subdomain, t.fake_mailing_address, t.fake_authorized_by, t.id]
      )
    end

    exec(
      conn,
      "UPDATE teams SET d4h_access_key_owner = NULL WHERE d4h_access_key_owner IS NOT NULL"
    )

    for [id, email] <- rows(conn, "SELECT id, email FROM users") do
      exec(conn, "UPDATE users SET email = ? WHERE id = ?", [
        Map.fetch!(emails, String.downcase(email)),
        id
      ])
    end

    exec(conn, "DELETE FROM users_tokens")
    exec(conn, "DELETE FROM oban_jobs")
    exec(conn, "DELETE FROM pass_registrations")

    for [id, email, reason] <- rows(conn, "SELECT id, email, reason FROM team_login_grants") do
      exec(conn, "UPDATE team_login_grants SET email = ?, reason = ? WHERE id = ?", [
        Map.get(emails, String.downcase(email), fake_email_for(email)),
        scrub.(reason),
        id
      ])
    end

    for [id, reason, error] <-
          rows(conn, "SELECT id, reason, error FROM group_membership_changes") do
      exec(conn, "UPDATE group_membership_changes SET reason = ?, error = ? WHERE id = ?", [
        scrub.(reason),
        scrub.(error),
        id
      ])
    end

    for [id] <- rows(conn, "SELECT id FROM member_cards") do
      token = App.Vault.encrypt!(Base.encode64(:crypto.strong_rand_bytes(24))) |> Base.encode64()

      exec(conn, "UPDATE member_cards SET code = ?, authentication_token = ? WHERE id = ?", [
        App.Model.MemberCard.generate_code(),
        token,
        id
      ])
    end

    for [id, name] <- rows(conn, "SELECT id, name FROM organizations") do
      place = pick(@places, {:organization, name})

      exec(
        conn,
        "UPDATE organizations SET name = ?, short_name = ?, slug = ?, website = NULL, logo = NULL WHERE id = ?",
        ["#{place} SAR Association", initials(place) <> "SARA", slug(place) <> "sara", id]
      )
    end

    sanitize_activities(conn, team_by_id, scrub)
    sanitize_letters(conn, people, team_by_id)
    check_for_leaks(conn, people, teams, emails)

    exec(conn, "COMMIT")
  end

  defp fake_teams(teams, kept_names) do
    {teams, _used} =
      Enum.map_reduce(teams, MapSet.new(), fn [id, name, subdomain, address, authorized_by],
                                              used ->
        place = unused_place({:team, id}, used)
        province = province(address)
        kept? = subdomain in @keep_teams
        suffix = Enum.find(@team_suffixes, "Search and Rescue", &String.contains?(name, &1))

        team = %{
          id: id,
          kept?: kept?,
          name: name,
          subdomain: subdomain,
          mailing_address: address,
          authorized_by: authorized_by,
          place: place,
          province: province,
          fake_name: if(kept?, do: name, else: "#{place} #{suffix}"),
          fake_subdomain: if(kept?, do: subdomain, else: slug(place) <> "sar"),
          fake_mailing_address:
            if(kept? or is_nil(address),
              do: address,
              else: "PO Box #{1000 + hash({:box, id}, 8000)}\n#{place}, #{province}"
            ),
          fake_authorized_by:
            fake_authorized_by(
              id,
              authorized_by,
              kept? and names_a_kept_person?(authorized_by, kept_names)
            )
        }

        {team, MapSet.put(used, place)}
      end)

    teams
  end

  defp unused_place(key, used) do
    start = hash(key, length(@places))

    Enum.find_value(0..(length(@places) - 1), fn i ->
      place = Enum.at(@places, rem(start + i, length(@places)))
      if place not in used, do: place
    end) || raise "More teams than fake places. Add places to @places."
  end

  # A kept team still loses a signer who isn't kept.
  defp names_a_kept_person?(nil, _kept_names), do: true

  defp names_a_kept_person?(value, kept_names) do
    Enum.any?(kept_names, &(&1 && String.contains?(String.downcase(value), String.downcase(&1))))
  end

  defp fake_authorized_by(_id, nil, _kept?), do: nil
  defp fake_authorized_by(_id, value, true), do: value

  defp fake_authorized_by(id, value, false) do
    role = value |> String.split(",", parts: 2) |> Enum.at(1)
    name = fake_name({:authorized_by, id}, false)
    if role, do: "#{name},#{role |> String.split("\n") |> hd()}", else: name
  end

  defp fake_people(members, kept?, team_by_id) do
    for [id, team_id, name, email, phone, address] = row <- members do
      team = Map.fetch!(team_by_id, team_id)
      # One person on two teams shares an email, so key the fakes on it when there is one.
      key = if email && email != "", do: String.downcase(email), else: {:member, id}

      %{
        id: id,
        kept?: kept?.(row),
        name: name,
        email: blank_to_nil(email),
        phone: blank_to_nil(phone),
        address: blank_to_nil(address),
        fake_name: name && fake_name(key, String.contains?(name, ",")),
        fake_phone: blank_to_nil(phone) && fake_phone(key, phone, team.province),
        fake_address: blank_to_nil(address) && fake_address(key, team)
      }
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(value), do: if(String.trim(value) == "", do: nil, else: value)

  defp fake_name(key, last_first?) do
    first = pick(@first_names, {:first, key})
    last = pick(@last_names, {:last, key})
    if last_first?, do: "#{last}, #{first}", else: "#{first} #{last}"
  end

  defp fake_phone(key, phone, province) do
    area = Map.get(@area_codes, province, "604")
    line = hash({:phone, key}, 10_000) |> Integer.to_string() |> String.pad_leading(4, "0")
    digits = String.replace(phone, ~r/\D/, "")

    cond do
      String.contains?(phone, "-") -> "#{area}-555-#{line}"
      String.length(digits) == 11 -> "1#{area}555#{line}"
      true -> "#{area}555#{line}"
    end
  end

  defp fake_address(key, team) do
    number = 100 + hash({:house, key}, 9900)
    street = pick(@streets, {:street, key})
    kind = pick(@street_kinds, {:kind, key})
    "#{number} #{street} #{kind}, #{team.place}, #{team.province}"
  end

  # Real email → fake, for members and users alike, unique because users.email is.
  defp fake_emails(conn, people, admins) do
    member_emails =
      people
      |> Enum.filter(& &1.email)
      |> Enum.uniq_by(&String.downcase(&1.email))
      |> Enum.sort_by(&String.downcase(&1.email))
      |> Enum.map(fn p ->
        real = String.downcase(p.email)
        if p.kept?, do: {real, p.email}, else: {real, email_from_name(p.fake_name)}
      end)

    user_emails =
      for [email] <- rows(conn, "SELECT email FROM users"),
          real = String.downcase(email),
          not List.keymember?(member_emails, real, 0) do
        if real in admins, do: {real, email}, else: {real, fake_email_for(email)}
      end

    {map, _} =
      Enum.reduce(member_emails ++ user_emails, {%{}, MapSet.new()}, fn {real, fake},
                                                                        {map, used} ->
        fake =
          if real in admins or real == String.downcase(fake),
            do: fake,
            else: unique(fake, real, used)

        {Map.put(map, real, fake), MapSet.put(used, String.downcase(fake))}
      end)

    map
  end

  defp fake_email_for(email), do: email_from_name(fake_name(String.downcase(email), false))

  defp email_from_name(name) do
    local =
      name
      |> String.split(", ")
      |> Enum.reverse()
      |> Enum.join(".")
      |> String.replace(" ", ".")
      |> String.downcase()

    local <> "@example.com"
  end

  defp unique(fake, real, used) do
    if String.downcase(fake) in used do
      [local, domain] = String.split(fake, "@")
      unique("#{local}#{hash({:dup, real, fake}, 100)}@#{domain}", real, used)
    else
      fake
    end
  end

  defp sanitize_activities(conn, team_by_id, scrub) do
    sql =
      "SELECT id, team_id, activity_kind, title, description, address, coordinate, tags FROM activities"

    for [id, team_id, kind, title, description, address, coordinate, tags] <- rows(conn, sql) do
      team = Map.fetch!(team_by_id, team_id)
      incident? = kind == "incident"

      title = if incident?, do: pick(@incident_titles, {:incident, id}), else: scrub.(title)
      description = blank_to_nil(description) && "Notes for this #{kind}."

      address =
        cond do
          is_nil(blank_to_nil(address)) -> address
          incident? -> "#{team.place}, #{team.province}"
          true -> scrub.(address)
        end

      coordinate = if incident?, do: jitter(coordinate, id), else: coordinate

      exec(
        conn,
        "UPDATE activities SET title = ?, description = ?, address = ?, coordinate = ?, tags = ? WHERE id = ?",
        [title, description, address, coordinate, scrub.(tags), id]
      )
    end
  end

  # Moves an incident 1–2 km, so the spot no longer points at someone's home.
  defp jitter(nil, _id), do: nil

  defp jitter(coordinate, id) do
    with [lat, lng] <- String.split(coordinate, ","),
         {lat, ""} <- Float.parse(String.trim(lat)),
         {lng, ""} <- Float.parse(String.trim(lng)),
         true <- lat != 0.0 or lng != 0.0 do
      angle = hash({:angle, id}, 360) * :math.pi() / 180
      km = 1 + hash({:km, id}, 1000) / 1000
      lat = lat + km / 111 * :math.sin(angle)
      lng = lng + km / (111 * :math.cos(lat * :math.pi() / 180)) * :math.cos(angle)
      :io_lib.format("~.5f,~.5f", [lat, lng]) |> to_string()
    else
      _ -> coordinate
    end
  end

  # Letters are rebuilt from the fakes, keeping the hours and the certified date.
  defp sanitize_letters(conn, people, team_by_id) do
    by_id = Map.new(people, &{&1.id, &1})

    sql = """
    SELECT l.id, l.member_id, l.ref_id, l.year, l.letter_content, m.team_id
    FROM tax_credit_letters l JOIN members m ON m.id = l.member_id
    """

    for [id, member_id, ref_id, year, content, team_id] <- rows(conn, sql) do
      p = Map.fetch!(by_id, member_id)

      unless p.kept? do
        team = Map.fetch!(team_by_id, team_id)
        content = letter(team, p, ref_id, year, decrypt_letter(content))
        exec(conn, "UPDATE tax_credit_letters SET letter_content = ? WHERE id = ?", [content, id])
      end
    end
  end

  # A copy taken before #113 still has letters under Cloak.
  defp decrypt_letter(content) do
    with {:ok, bytes} <- Base.decode64(content),
         plain when is_binary(plain) <- App.Vault.decrypt!(bytes) do
      plain
    else
      _ -> content
    end
  rescue
    _ -> content
  end

  defp letter(team, p, ref_id, year, old) do
    line = fn label ->
      case Regex.run(~r/#{label}: (.*)/, old) do
        [_, value] -> value
        _ -> "0 hours"
      end
    end

    certified =
      case Regex.run(~r/Certified on (.*)\./, old) do
        [_, value] -> value
        _ -> "January 15, #{year + 1}"
      end

    """
    #{team.fake_mailing_address}


    To whom it may concern:

    Name: #{p.fake_name}
    Address: #{p.fake_address}

    This letter serves to confirm that the above noted individual has completed eligible volunteer search and rescue hours for #{team.fake_name}, an ‘Eligible Search and Rescue Organization recognized by the RCMP’ in the #{year} calendar year.

    Primary Hours: #{line.("Primary Hours")}
    Secondary Hours: #{line.("Secondary Hours")}
    Total Hours: #{line.("Total Hours")}

    Please contact the writer if you have any questions.

    Certified on #{certified}.




    #{team.fake_authorized_by || team.fake_name}

    Reference: #{ref_id}
    """
  end

  # ---- Replacing and finding real values in free text

  defp replacements(people, teams, emails) do
    people_pairs =
      for p <- people,
          not p.kept?,
          {real, fake} <- [{p.name, p.fake_name}, {p.address, p.fake_address}],
          do: {real, fake}

    team_pairs =
      for t <- teams,
          not t.kept?,
          {real, fake} <- [{t.name, t.fake_name}, {t.subdomain, initials(t.place) <> "SAR"}],
          do: {real, fake}

    pairs = Enum.to_list(emails) ++ people_pairs ++ team_pairs

    map =
      for {real, fake} <- pairs, real, String.length(real) >= 4, real != fake, into: %{} do
        {String.downcase(real, :ascii), fake}
      end

    {compile(Map.keys(map)), map}
  end

  defp scrub(nil, _replacements), do: nil
  defp scrub(text, {nil, _map}), do: text

  defp scrub(text, {pattern, map}) do
    # :ascii keeps byte offsets the same, so matches in the lowercase copy splice the original.
    lower = String.downcase(text, :ascii)

    {parts, last} =
      Enum.reduce(:binary.matches(lower, pattern), {[], 0}, fn {at, len}, {parts, from} ->
        fake = Map.fetch!(map, binary_part(lower, at, len))
        {[fake, binary_part(text, from, at - from) | parts], at + len}
      end)

    IO.iodata_to_binary(Enum.reverse([binary_part(text, last, byte_size(text) - last) | parts]))
  end

  defp compile([]), do: nil
  defp compile(needles), do: :binary.compile_pattern(needles)

  defp check_for_leaks(conn, people, teams, emails) do
    fakes =
      MapSet.new(
        Enum.flat_map(people, &[&1.fake_name, &1.fake_address, &1.fake_phone]) ++
          Enum.flat_map(teams, &[&1.fake_name, &1.fake_subdomain, &1.fake_mailing_address]) ++
          Map.values(emails),
        &(&1 && String.downcase(&1, :ascii))
      )

    kept =
      MapSet.new(
        Enum.flat_map(Enum.filter(people, & &1.kept?), &[&1.name, &1.email, &1.phone, &1.address]) ++
          Enum.flat_map(
            Enum.filter(teams, & &1.kept?),
            &[&1.name, &1.mailing_address, &1.authorized_by]
          ),
        &(&1 && String.downcase(&1, :ascii))
      )

    needles =
      (Enum.flat_map(Enum.reject(people, & &1.kept?), &[&1.name, &1.email, &1.phone, &1.address]) ++
         Enum.flat_map(Enum.reject(teams, & &1.kept?), fn t ->
           [t.name, t.subdomain, t.authorized_by | String.split(t.mailing_address || "", "\n")]
         end))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&(&1 |> String.trim() |> String.downcase(:ascii)))
      |> Enum.filter(&(String.length(&1) >= 5))
      |> Enum.reject(&(MapSet.member?(fakes, &1) or MapSet.member?(kept, &1)))
      |> Enum.uniq()

    pattern = compile(needles)

    leaks =
      for table <- tables(conn),
          col <- text_columns(conn, table),
          [id, value] <-
            rows(conn, ~s(SELECT rowid, "#{col}" FROM "#{table}" WHERE "#{col}" IS NOT NULL)),
          is_binary(value),
          pattern,
          match = :binary.match(String.downcase(value, :ascii), pattern),
          match != :nomatch do
        {at, len} = match
        "#{table}.#{col} row #{id}: #{binary_part(String.downcase(value, :ascii), at, len)}"
      end

    if leaks != [] do
      exec(conn, "ROLLBACK")

      leaks
      |> Enum.frequencies_by(&String.replace(&1, ~r/ row \d+/, ""))
      |> Enum.each(fn {leak, n} -> IO.puts("#{n}× #{leak}") end)

      raise "#{length(leaks)} real values are still in the copy. Nothing was written."
    end

    IO.puts("Checked #{length(needles)} real values across every text column: none left.")
  end

  defp tables(conn) do
    rows(conn, "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
    |> Enum.map(&hd/1)
    |> Enum.reject(&(&1 == "schema_migrations"))
  end

  defp text_columns(conn, table) do
    for [_, name, type | _] <- rows(conn, "PRAGMA table_info(\"#{table}\")"),
        String.upcase(type) in ["TEXT", "JSON", ""],
        do: name
  end

  # ---- Helpers

  defp province(nil), do: "BC"

  defp province(address) do
    case Regex.run(~r/\b(BC|AB|SK|MB|ON|QC|NB|NS|PE|NL|YT|NT|NU)\b/, address) do
      [_, province] -> province
      _ -> "BC"
    end
  end

  defp pick(list, key), do: Enum.at(list, hash(key, length(list)))
  defp hash(key, range), do: :erlang.phash2(key, range)
  defp slug(place), do: place |> String.downcase() |> String.replace(~r/[^a-z]/, "")
  defp initials(place), do: place |> String.split() |> Enum.map_join(&String.first/1)

  defp rows(conn, sql, args \\ []) do
    {:ok, statement} = Exqlite.Sqlite3.prepare(conn, sql)
    :ok = Exqlite.Sqlite3.bind(statement, args)
    {:ok, rows} = Exqlite.Sqlite3.fetch_all(conn, statement)
    :ok = Exqlite.Sqlite3.release(conn, statement)
    rows
  end

  defp exec(conn, sql, args \\ []), do: rows(conn, sql, args)
end

Sanitize.run(System.argv())
