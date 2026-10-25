defmodule App.Operation.SaveOrganizationHoursTags do
  @moduledoc """
  Saves the hours tags an organization's teams count (#289, #512), from its Hours tags
  settings. Records the old and new tags, so a question about a letter's hours can be
  traced. No pass updates: hours tags are not on a pass. Letters already made keep
  their hours.
  """

  import Ecto.Query

  alias App.Accounts.User
  alias App.Model.Activity
  alias App.Model.Event
  alias App.Model.Organization
  alias App.Model.Team
  alias App.Repo

  def call(%Organization{} = organization, params, %User{} = user) do
    teams = Team |> where([t], t.organization_id == ^organization.id) |> Repo.all()
    changeset = Organization.build_hours_tags_changeset(organization, teams, params)

    with {:ok, saved} <- Repo.update(changeset) do
      before = Activity.organization_hours_tags(organization)
      now = Activity.organization_hours_tags(saved)

      if before != now do
        Event.record!(:organization_hours_tags_changed,
          user_id: user.id,
          data: %{organization_id: saved.id, before: before, after: now}
        )
      end

      {:ok, saved}
    end
  end
end
