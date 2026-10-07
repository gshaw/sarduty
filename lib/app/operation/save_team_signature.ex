defmodule App.Operation.SaveTeamSignature do
  alias App.Model.Team
  alias App.Repo

  # Wide enough to stay sharp at 3 inches on a printed letter.
  @max_side 900

  @doc """
  Saves an uploaded signature (raw PNG or JPEG bytes, any size) as the team's PNG, or
  removes it when given nil. Letters already made keep the signature they have.
  """
  def call(%Team{} = team, nil),
    do: {:ok, team |> Ecto.Changeset.change(signature: nil) |> Repo.update!()}

  def call(%Team{} = team, bytes) when is_binary(bytes) do
    case Service.Image.png(bytes, @max_side) do
      {:ok, png} -> {:ok, team |> Ecto.Changeset.change(signature: png) |> Repo.update!()}
      {:error, _reason} -> {:error, :image}
    end
  end
end
