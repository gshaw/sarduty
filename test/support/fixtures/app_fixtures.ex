defmodule App.DataFixtures do
  alias App.Accounts.User
  alias App.AccountsFixtures
  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
  alias App.Model.TaxCreditLetter
  alias App.Model.Team
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

  def user_with_team_fixture(attrs \\ %{}) do
    user = AccountsFixtures.user_fixture()
    team = team_fixture(Map.get(attrs, :team, %{}))

    {:ok, user} =
      User.update(user, %{
        team_id: team.id,
        d4h_access_key: Map.get(attrs, :d4h_access_key, "d4h-access-key")
      })

    %{user: user, team: team}
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

    Activity.insert!(params)
  end

  def member_fixture(%Team{} = team, attrs \\ %{}) do
    unique = System.unique_integer([:positive])

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

    Member.insert!(params)
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
