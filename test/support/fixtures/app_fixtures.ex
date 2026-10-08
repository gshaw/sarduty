defmodule App.DataFixtures do
  alias App.AccountsFixtures
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Group
  alias App.Model.GroupMember
  alias App.Model.GroupRuleClause
  alias App.Model.GroupRuleClauseQualification
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.MemberQualificationAward
  alias App.Model.Organization
  alias App.Model.Qualification
  alias App.Model.TaxCreditLetter
  alias App.Model.Team
  alias App.Operation.CreateHostedTeam
  alias App.Repo

  def team_fixture(attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    params =
      Map.merge(
        %{
          name: "Team #{unique}",
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

    Team.insert!(params)
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

    Organization.set_teams!(organization, Enum.map(teams, & &1.id))
    organization
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

  @doc """
  A team without D4H (docs/hosted-d4h.md), refreshed from its store, with a user who
  manages it. `sample_data: true` fills it with made-up records.
  """
  def hosted_team_with_user_fixture(attrs \\ %{}) do
    user = AccountsFixtures.user_fixture()
    unique = System.unique_integer([:positive])

    {:ok, team} =
      CreateHostedTeam.call(%{
        "name" => "Hosted #{unique}",
        "subdomain" => "hosted#{unique}",
        "timezone" => "America/Halifax",
        "manager_name" => "Robin Example",
        "manager_email" => user.email,
        "sample_data" => Map.get(attrs, :sample_data, false)
      })

    %{user: user, team: team}
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
          tags: [Activity.primary_hours_tag()]
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

  def attendance_fixture(%Activity{} = activity, %Member{} = member, attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    params =
      Map.merge(
        %{
          activity_id: activity.id,
          member_id: member.id,
          d4h_attendance_id: unique,
          duration_in_minutes: 60,
          started_at: DateTime.utc_now() |> DateTime.truncate(:second),
          finished_at: DateTime.utc_now() |> DateTime.truncate(:second),
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

  def group_rule_clause_fixture(%Group{} = group, attrs \\ %{}) do
    {on_card, attrs} = Map.pop(attrs, :on_card, false)

    %{team_id: group.team_id, d4h_group_id: group.d4h_group_id}
    |> Map.merge(attrs)
    |> GroupRuleClause.insert!()
    |> Ecto.Changeset.change(on_card: on_card)
    |> Repo.update!()
  end

  def group_rule_clause_qualification_fixture(
        %GroupRuleClause{} = clause,
        %Qualification{} = qualification
      ) do
    GroupRuleClauseQualification.insert!(%{
      group_rule_clause_id: clause.id,
      d4h_qualification_id: qualification.d4h_qualification_id
    })
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
end
