defmodule Web.OwnDetails do
  @moduledoc """
  A member with a login, an address, and an emergency contact, for the tests of the
  Change pages on Your membership, and a D4H that takes their PATCH.
  """

  import App.DataFixtures
  import Web.ConnCase, only: [log_in_user: 2]

  alias App.Repo

  @doc "The member, their team with a key, their user, and a conn logged in as them."
  def member_logged_in(%{conn: conn}) do
    %{team: team, member: member, user: user} =
      member_with_login_fixture(%{
        address: "1 Main St",
        primary_emergency_contact: %{
          "name" => "Sam Rivera",
          "relation" => "Partner",
          "primary_phone" => "604-555-0100",
          "secondary_phone" => nil
        }
      })

    team = team |> Ecto.Changeset.change(d4h_access_key: "key") |> Repo.update!()
    %{conn: log_in_user(conn, user), team: team, member: member, user: user}
  end

  @doc """
  Sends each PATCH body to the test process as `{:patch, path, body}`. The pages read
  the copy, so a GET fails the test.
  """
  def stub_d4h(team, member) do
    test = self()

    Req.Test.stub(App.Adapter.D4H, fn %{method: "PATCH"} = conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:patch, conn.request_path, Jason.decode!(body)})
      Req.Test.json(conn, d4h_member(team, member))
    end)
  end

  defp d4h_member(team, member) do
    %{
      "id" => member.d4h_member_id,
      "name" => member.name,
      "owner" => %{"resourceType" => "Team", "id" => team.d4h_team_id},
      "email" => %{"value" => member.email},
      "mobile" => %{"phone" => nil},
      "deprecatedAddress" => "1 Main St",
      "primaryEmergencyContact" => %{
        "name" => "Sam Rivera",
        "relation" => "Partner",
        "primaryPhone" => "604-555-0100",
        "secondaryPhone" => ""
      },
      "secondaryEmergencyContact" => nil
    }
  end
end
