defmodule App.Operation.SaveOrganization do
  alias App.Adapter.FileStore
  alias App.Model.Organization
  alias App.Repo
  alias App.Worker.PushPassUpdatesWorker

  require Logger

  @doc """
  Saves an organization's General settings (#512): its fields, and a new logo when one
  was uploaded (raw image bytes, any size). Its teams get their passes rebuilt, since
  the back of the pass names the organization. The logo is a file in the store
  (`Organization.logo_key/1`), and `logo_at` says when it was saved. Teams join and leave through
  App.Operation.SetTeamOrganization, never here.
  """
  def call(%Organization{} = organization, params, logo_bytes, now \\ DateTime.utc_now()) do
    changeset = Organization.build_changeset(organization, params)

    # The logo goes to the file store before the row changes (#1067), so a store that
    # refuses it saves nothing.
    with {:ok, logo} <- shape_logo(logo_bytes),
         :ok <- put_logo(organization, logo),
         changeset = if(logo, do: Ecto.Changeset.change(changeset, logo_at: now), else: changeset),
         {:ok, organization} <- Repo.update(changeset) do
      organization |> Organization.team_ids() |> PushPassUpdatesWorker.enqueue_team_ids()

      {:ok, organization}
    else
      {:error, :logo} -> {:error, logo_error(changeset, "Use a PNG or JPEG image.")}
      {:error, :store} -> {:error, logo_error(changeset, "Logo not saved. Try again.")}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp logo_error(changeset, message),
    do: Ecto.Changeset.add_error(%{changeset | action: :validate}, :logo, message)

  defp put_logo(_organization, nil), do: :ok

  defp put_logo(organization, png) do
    case organization |> Organization.logo_key() |> FileStore.put(png, "image/png") do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("organization logo not saved: #{inspect(reason)}")
        {:error, :store}
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
