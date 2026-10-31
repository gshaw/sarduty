defmodule App.DataFixtures do
  alias App.AccountsFixtures
  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Certificate
  alias App.Model.CertificateFile
  alias App.Model.Chore
  alias App.Model.ChoreCategory
  alias App.Model.ChoreEvent
  alias App.Model.Endorsement
  alias App.Model.EndorsementQualification
  alias App.Model.EquipmentItem
  alias App.Model.EquipmentUsage
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.GroupRule
  alias App.Model.Member
  alias App.Model.MemberAwayPeriod
  alias App.Model.MemberCard
  alias App.Model.MemberQualificationAward
  alias App.Model.Organization
  alias App.Model.Qualification
  alias App.Model.Tag
  alias App.Model.TaxCreditLetter
  alias App.Model.Team
  alias App.Model.Template
  alias App.Model.TemplateGroup
  alias App.Model.TemplateItem
  alias App.Model.TemplateTag
  alias App.Repo

  require Ecto.Query

  # ID cards are on, as for every team that signed up before the switch; pass
  # `id_cards_enabled: false` for a team an admin hasn't turned them on for.
  def team_fixture(attrs \\ %{}) do
    unique = System.unique_integer([:positive])
    # On, like a team that uses them; each is off on a new team.
    {id_cards_enabled, attrs} = Map.pop(attrs, :id_cards_enabled, true)
    {whiteboard_enabled, attrs} = Map.pop(attrs, :whiteboard_enabled, true)

    name = Map.get(attrs, :name, "Team #{unique}")

    params =
      Map.merge(
        %{
          name: name,
          legal_name: name,
          abbreviated_name: "TEAM",
          subdomain: "team#{unique}",
          d4h_team_id: unique,
          d4h_api_host: "api.ca.d4h.org",
          mailing_address: "123 Main St",
          lat: 49.2,
          lng: -123.1,
          timezone: "America/Vancouver"
        },
        attrs
      )

    params
    |> Team.insert!()
    |> Ecto.Changeset.change(
      id_cards_enabled: id_cards_enabled,
      whiteboard_enabled: whiteboard_enabled
    )
    |> Repo.update!()
  end

  @doc "An organization with a logo, and these teams as members."
  def organization_fixture(teams \\ [], attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    organization =
      %Organization{
        name: "Example Association #{unique}",
        short_name: "EXA",
        slug: "exa-#{unique}",
        logo: png_fixture(200, 200)
      }
      |> Map.merge(attrs)
      |> Repo.insert!()

    ids = Enum.map(teams, & &1.id)

    Team
    |> Ecto.Query.where([t], t.id in ^ids)
    |> Repo.update_all(set: [organization_id: organization.id])

    organization
  end

  @doc "An organization admin (#512), inserted directly, so any email works."
  def organization_admin_fixture(%Organization{} = organization, email, attrs \\ %{}) do
    %App.Model.OrganizationAdmin{organization_id: organization.id, email: String.downcase(email)}
    |> Map.merge(attrs)
    |> Repo.insert!()
  end

  @doc "A note on the team's whiteboard (#515), live for a week unless `archived_at` says."
  def whiteboard_note_fixture(%Team{} = team, attrs \\ %{}) do
    now = DateTime.utc_now(:second)

    %App.Model.WhiteboardNote{
      team_id: team.id,
      d4h_whiteboard_note_id: System.unique_integer([:positive]),
      text: "Pager test Sunday at 10:00.",
      archived_at: DateTime.add(now, 7, :day),
      d4h_created_at: DateTime.add(now, -1, :day)
    }
    |> struct!(attrs)
    |> Repo.insert!()
  end

  @doc "A copy of one of the team's location bookmarks (#614), the sync's row."
  def location_bookmark_fixture(%Team{} = team, attrs \\ %{}) do
    %App.Model.LocationBookmark{
      team_id: team.id,
      d4h_location_bookmark_id: System.unique_integer([:positive]),
      title: "Hall",
      address: "17543 20 Ave, Surrey",
      coordinate: "49.03879,-122.73734"
    }
    |> struct!(attrs)
    |> Repo.insert!()
  end

  @doc "A team with member logins on (#156), so its current members may log in."
  def member_logins_team_fixture(attrs \\ %{}) do
    # Chores (#341) and certificates (#493) need their own settings too; tests of them
    # use this team.
    attrs
    |> team_fixture()
    |> Ecto.Changeset.change(
      member_logins: true,
      chores_enabled: true,
      certificates_enabled: true
    )
    |> Repo.update!()
  end

  @doc "A team with member logins on, a member on it, and that member's user."
  def member_with_login_fixture(attrs \\ %{}) do
    team = member_logins_team_fixture()
    member = team |> member_fixture(Map.merge(%{d4h_permission: 2}, attrs)) |> Repo.preload(:team)
    user = AccountsFixtures.user_fixture(%{email: member.email})
    %{team: team, member: member, user: user}
  end

  @doc """
  Now, this year in the team's time zone, and `mid_year`: earlier this year, an hour ago
  or the second the year began, which is never after now. Only rows that have started
  count as attended.
  """
  def this_year_fixture(team) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    year = Service.YearRange.year_in(now, team.timezone)
    {start_of_year, _finish} = Service.YearRange.bounds(year, team.timezone)
    mid_year = Enum.max([DateTime.add(now, -1, :hour), start_of_year], DateTime)
    %{year: year, mid_year: mid_year, now: now}
  end

  @doc "PNG bytes of a plain image, as D4H sends a photo or logo."
  def png_fixture(width, height) do
    width |> Image.new!(height, color: :steelblue) |> Image.write!(:memory, suffix: ".png")
  end

  # Call from a test: the file is removed when the test exits.
  def team_logo_fixture(team, bytes \\ "png bytes") do
    path = Team.logo_path(team.subdomain)
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, bytes)
    ExUnit.Callbacks.on_exit(fn -> File.rm(path) end)
    path
  end

  @doc """
  Makes every email fail until the test ends, as Cloudflare refusing it. It changes the
  app's config, so only a test that isn't async may use it.
  """
  def refusing_mailer_fixture do
    original = Application.get_env(:sarduty, App.Mailer)
    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:sarduty, App.Mailer, original) end)

    Application.put_env(:sarduty, App.Mailer,
      adapter: App.Adapter.CloudflareEmail,
      account_id: "test",
      api_token: "test",
      req_options: [plug: {Req.Test, App.Adapter.CloudflareEmail}, retry: false]
    )

    Req.Test.stub(App.Adapter.CloudflareEmail, fn conn ->
      conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"success" => false})
    end)
  end

  def make_admin(user) do
    user
    |> Ecto.Changeset.change(%{is_admin: true})
    |> Repo.update!()
  end

  @doc "A team, and a user who reaches it as a D4H Owner with the same email."
  def user_with_team_fixture(attrs \\ %{}) do
    user = AccountsFixtures.user_fixture()
    team = team_fixture(Map.get(attrs, :team, %{}))
    manager_fixture(team, %{email: user.email})
    %{user: user, team: team}
  end

  @doc "The same, for a team on SAR Duty Records (docs/records.md)."
  def records_team_with_user_fixture(attrs \\ %{}) do
    team_attrs = Map.merge(%{d4h_api_host: D4H.records_host()}, attrs)
    user_with_team_fixture(%{team: team_attrs})
  end

  @doc "A member the team picks as its first team contact (#780). Returns the team."
  def team_contact_fixture(%Team{} = team, attrs \\ %{}) do
    contact = member_fixture(team, attrs)
    team |> Ecto.Changeset.change(first_contact_id: contact.id) |> App.Repo.update!()
  end

  @doc "A member D4H makes an Owner, so a user with their email manages the team."
  def manager_fixture(%Team{} = team, attrs \\ %{}) do
    member_fixture(team, Map.merge(%{d4h_permission: 0, d4h_status: "OPERATIONAL"}, attrs))
  end

  def activity_fixture(%Team{} = team, attrs \\ %{}) do
    unique = System.unique_integer([:positive])
    started_at = DateTime.utc_now() |> DateTime.truncate(:second)
    finished_at = DateTime.add(started_at, 3600, :second)

    params =
      Map.merge(
        %{
          team_id: team.id,
          d4h_activity_id: unique,
          ref_id: "A#{unique}",
          tracking_number: "TRK#{unique}",
          is_published: false,
          title: "Activity #{unique}",
          description: "Test activity",
          address: "123 Main St",
          coordinate: "49.1,-123.1",
          activity_kind: "exercise",
          hours_kind: "primary",
          started_at: started_at,
          finished_at: finished_at,
          tags: ["Primary Hours"]
        },
        attrs
      )

    # The refresh sets `deleted_at` itself; the changeset never casts it.
    {deleted_at, params} = Map.pop(params, :deleted_at)
    activity = Activity.insert!(params)

    if deleted_at,
      do: activity |> Ecto.Changeset.change(deleted_at: deleted_at) |> Repo.update!(),
      else: activity
  end

  # `not_a_person` is set in SAR Duty, not copied from D4H, so it skips the changeset.
  def member_fixture(%Team{} = team, attrs \\ %{}) do
    unique = System.unique_integer([:positive])
    {not_a_person, attrs} = Map.pop(attrs, :not_a_person, false)

    params =
      Map.merge(
        %{
          team_id: team.id,
          d4h_member_id: unique,
          ref_id: "M#{unique}",
          name: "Member #{unique}",
          email: "member#{unique}@example.com",
          phone: "555-000-#{unique}",
          address: "123 Main St",
          position: "Responder",
          joined_at: DateTime.utc_now() |> DateTime.truncate(:second)
        },
        attrs
      )

    member = Member.insert!(params)

    if not_a_person,
      do: member |> Ecto.Changeset.change(not_a_person: true) |> Repo.update!(),
      else: member
  end

  # The row starts and ends with its activity, as D4H's do unless someone edits them.
  def attendance_fixture(%Activity{} = activity, %Member{} = member, attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    params =
      Map.merge(
        %{
          activity_id: activity.id,
          member_id: member.id,
          d4h_attendance_id: unique,
          duration_in_minutes: 60,
          started_at: activity.started_at,
          finished_at: activity.finished_at,
          status: "attending"
        },
        attrs
      )

    Attendance.insert!(params)
  end

  def qualification_fixture(%Team{} = team, attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    params =
      Map.merge(
        %{
          team_id: team.id,
          d4h_qualification_id: unique,
          title: "Qualification #{unique}"
        },
        attrs
      )

    Qualification.insert!(params)
  end

  def qualification_award_fixture(
        %Qualification{} = qualification,
        %Member{} = member,
        attrs \\ %{}
      ) do
    unique = System.unique_integer([:positive])

    params =
      Map.merge(
        %{
          qualification_id: qualification.id,
          member_id: member.id,
          d4h_award_id: unique,
          starts_at: DateTime.utc_now() |> DateTime.truncate(:second),
          ends_at: nil
        },
        attrs
      )

    MemberQualificationAward.insert!(params)
  end

  @doc "An award with a certificate in D4H (#314), document 77 unless given another."
  def certificate_award_fixture(%Team{} = team, %Member{} = member, attrs \\ %{}) do
    qualification = qualification_fixture(team, %{title: "Standard First Aid"})
    award = qualification_award_fixture(qualification, member, attrs)
    document_id = Map.get(attrs, :d4h_document_id, 77)
    MemberQualificationAward.set_documents([{award.id, document_id}])
    %{award | d4h_document_id: document_id}
  end

  def group_fixture(%Team{} = team, attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    params =
      Map.merge(
        %{
          team_id: team.id,
          d4h_group_id: unique,
          title: "Group #{unique}"
        },
        attrs
      )

    Group.insert!(params)
  end

  def group_member_fixture(%Group{} = group, %Member{} = member) do
    GroupMember.insert!(%{
      group_id: group.id,
      member_id: member.id,
      d4h_group_membership_id: System.unique_integer([:positive])
    })
  end

  @doc "An away period for the member (#366), its days on the team's clock."
  def away_period_fixture(%Member{} = member, starts_on, ends_on, attrs \\ %{}) do
    %MemberAwayPeriod{
      team_id: member.team_id,
      member_id: member.id,
      starts_on: starts_on,
      ends_on: ends_on,
      reason: "Leave"
    }
    |> struct(attrs)
    |> Repo.insert!()
  end

  def endorsement_fixture(%Team{} = team, attrs \\ %{}) do
    {on_card, attrs} = Map.pop(attrs, :on_card, false)
    attrs = Map.put_new(attrs, :name, "Endorsement #{System.unique_integer([:positive])}")
    {:ok, endorsement} = Endorsement.insert(team, attrs)
    endorsement |> Ecto.Changeset.change(on_card: on_card) |> Repo.update!()
  end

  def endorsement_qualification_fixture(
        %Endorsement{} = endorsement,
        %Qualification{} = qualification
      ),
      do: EndorsementQualification.insert!(endorsement, qualification.d4h_qualification_id)

  @doc "A rule on `group` with one group or endorsement: In unless `kind` says Not in."
  def group_rule_fixture(%Group{} = group, target, kind \\ :in) do
    {:ok, rule} = GroupRule.add!(group, kind, target)
    rule
  end

  def member_card_fixture(%Member{} = member, attrs \\ %{}) do
    %MemberCard{
      team_id: member.team_id,
      member_id: member.id,
      code: MemberCard.generate_code(),
      serial_number: "member-#{member.id}"
    }
    |> Map.merge(attrs)
    |> Repo.insert!()
  end

  def tax_credit_letter_fixture(%Member{} = member, attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    params =
      Map.merge(
        %{
          member_id: member.id,
          ref_id: "TCL#{unique}",
          year: Date.utc_today().year - 1,
          letter_content: "Test letter content"
        },
        attrs
      )

    params
    |> TaxCreditLetter.build_new_changeset()
    |> Repo.insert!()
  end

  @doc """
  A D4H custom field copied for the team (#681): an incident text field unless `attrs`
  say otherwise. `d4h_custom_field_id` defaults to a unique number.
  """
  def custom_field_fixture(%Team{} = team, attrs \\ %{}) do
    params =
      Map.merge(
        %{
          team_id: team.id,
          d4h_custom_field_id: System.unique_integer([:positive]),
          target: "incident",
          title: "Field",
          field_type: "text",
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        },
        attrs
      )

    App.Model.CustomField |> struct!(params) |> Repo.insert!()
  end

  def equipment_item_fixture(%Team{} = team, attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    params =
      Map.merge(
        %{
          team_id: team.id,
          d4h_equipment_id: unique,
          title: "Item #{unique}",
          item_type: "equipment",
          kind: "Radio",
          status: "operational",
          location_title: "Yard"
        },
        attrs
      )

    %EquipmentItem{} |> EquipmentItem.build_changeset(params) |> Repo.insert!()
  end

  def equipment_usage_fixture(%Activity{} = activity, %EquipmentItem{} = item, attrs \\ %{}) do
    params =
      Map.merge(
        %{
          team_id: activity.team_id,
          activity_id: activity.id,
          equipment_item_id: item.id,
          d4h_equipment_usage_id: System.unique_integer([:positive]),
          minutes: 120
        },
        attrs
      )

    %EquipmentUsage{} |> EquipmentUsage.build_changeset(params) |> Repo.insert!()
  end

  def template_fixture(%Team{} = team, title \\ "Truck 1", items \\ [], tags \\ [], groups \\ []) do
    template_items =
      for {item, minutes} <- items,
          do: %TemplateItem{equipment_item_id: item.id, minutes: minutes}

    template_tags = for tag <- tags, do: %TemplateTag{tag_id: tag.id}
    template_groups = for group <- groups, do: %TemplateGroup{group_id: group.id}

    Repo.insert!(%Template{
      team_id: team.id,
      title: title,
      template_items: template_items,
      template_tags: template_tags,
      template_groups: template_groups
    })
  end

  def tag_fixture(%Team{} = team, title) do
    Repo.insert!(%Tag{
      team_id: team.id,
      d4h_tag_id: System.unique_integer([:positive]),
      title: title
    })
  end

  def chore_category_fixture(%Team{} = team, attrs \\ %{}) do
    %ChoreCategory{team_id: team.id, title: "Equipment maintenance", hours: :primary}
    |> Map.merge(attrs)
    |> Repo.insert!()
  end

  @doc "A waiting chore of `member`'s, done yesterday on the team's clock."
  def chore_fixture(%Member{} = member, %ChoreCategory{} = category, attrs \\ %{}) do
    team = Repo.get!(Team, member.team_id)
    today = Service.Period.today(DateTime.utc_now(), team.timezone)

    %Chore{
      team_id: member.team_id,
      member_id: member.id,
      chore_category_id: category.id,
      date: Date.add(today, -1),
      minutes: 60,
      description: "Truck 1 wash"
    }
    |> Map.merge(attrs)
    |> Repo.insert!()
  end

  @doc """
  A chore activity (#575): a D4H event that lasts no time, SAR Duty's chore event for it,
  and an accepted chore of `minutes` for each entry, each by a new member. `attrs` go on
  the activity.
  """
  def chore_activity_fixture(%Team{} = team, minutes, attrs \\ %{}) do
    category = chore_category_fixture(team)
    start = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)

    activity =
      activity_fixture(
        team,
        Map.merge(
          %{
            title: "Chores: Equipment maintenance",
            activity_kind: "event",
            started_at: start,
            finished_at: start
          },
          attrs
        )
      )

    event =
      Repo.insert!(%ChoreEvent{
        team_id: team.id,
        chore_category_id: category.id,
        month: Date.beginning_of_month(DateTime.to_date(start)),
        d4h_activity_id: activity.d4h_activity_id
      })

    for m <- minutes do
      team
      |> member_fixture()
      |> chore_fixture(category, %{minutes: m, status: :accepted, chore_event_id: event.id})
    end

    activity
  end

  @doc """
  `team`'s chore event for `activity`'s D4H id, which makes it a chore activity (#575)
  when the activity is the team's own.
  """
  def chore_event_fixture(%Team{} = team, %Activity{} = activity) do
    Repo.insert!(%ChoreEvent{
      team_id: team.id,
      chore_category_id: chore_category_fixture(team).id,
      month: Date.beginning_of_month(DateTime.to_date(activity.started_at)),
      d4h_activity_id: activity.d4h_activity_id
    })
  end

  @doc "A certificate the member sent (#493), waiting, with a small PDF as its file."
  def certificate_fixture(%Member{} = member, %Qualification{} = qualification, attrs \\ %{}) do
    certificate =
      %Certificate{
        team_id: member.team_id,
        member_id: member.id,
        qualification_id: qualification.id,
        starts_on: ~D[2026-10-18],
        ends_on: ~D[2029-10-18],
        file_name: "first-aid.pdf",
        content_type: "application/pdf",
        file_size: 9
      }
      |> Map.merge(attrs)
      |> Repo.insert!()

    if certificate.status == :waiting, do: CertificateFile.put!(certificate, "%PDF-1.7\n")
    certificate
  end
end
