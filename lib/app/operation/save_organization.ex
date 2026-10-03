defmodule App.Operation.SaveOrganization do
  alias App.Model.Organization
  alias App.Repo
  alias App.Worker.PushPassUpdatesWorker

  @doc """
  Creates or updates an organization from the admin form: its fields, a new logo when
  one was uploaded (raw image bytes, any size), and exactly these member teams. Every
  team it had or now has gets its passes rebuilt, since the back of the pass names the
  organization.
  """
  def call(%Organization{} = organization, params, logo_bytes, team_ids) do
    changeset = Organization.build_changeset(organization, params)

    with {:ok, logo} <- shape_logo(logo_bytes),
         {:ok, organization} <- Repo.insert_or_update(changeset) do
      organization = if logo, do: Organization.put_logo!(organization, logo), else: organization
      before = Organization.team_ids(organization)
      Organization.set_teams!(organization, team_ids)

      for team_id <- Enum.uniq(before ++ team_ids) do
        %{team_id: team_id} |> PushPassUpdatesWorker.new() |> Oban.insert!()
      end

      {:ok, organization}
    else
      {:error, :logo} ->
        {:error,
         Ecto.Changeset.add_error(%{changeset | action: :validate}, :logo, "isn't an image")}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  # Wallet fits the Apple logo in a 480-pixel strip, so nothing needs more.
  defp shape_logo(nil), do: {:ok, nil}

  defp shape_logo(bytes) do
    case Service.Image.png(bytes, 480) do
      {:ok, png} -> {:ok, png}
      {:error, _reason} -> {:error, :logo}
    end
  end
end
