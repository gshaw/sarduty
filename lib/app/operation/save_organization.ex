defmodule App.Operation.SaveOrganization do
  alias App.Model.Organization
  alias App.Repo
  alias App.Worker.PushPassUpdatesWorker

  @doc """
  Saves an organization's General settings (#512): its fields, and a new logo when one
  was uploaded (raw image bytes, any size). Its teams get their passes rebuilt, since
  the back of the pass names the organization. Teams join and leave through
  App.Operation.SetTeamOrganization, never here.
  """
  def call(%Organization{} = organization, params, logo_bytes) do
    changeset = Organization.build_changeset(organization, params)

    with {:ok, logo} <- shape_logo(logo_bytes),
         {:ok, organization} <- Repo.update(changeset) do
      organization = if logo, do: Organization.put_logo!(organization, logo), else: organization

      for team_id <- Organization.team_ids(organization) do
        %{team_id: team_id} |> PushPassUpdatesWorker.new() |> Oban.insert!()
      end

      {:ok, organization}
    else
      {:error, :logo} ->
        {:error,
         Ecto.Changeset.add_error(
           %{changeset | action: :validate},
           :logo,
           "Use a PNG or JPEG image."
         )}

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
