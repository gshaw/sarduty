defmodule App.Operation.FeatureActivityPhoto do
  @moduledoc """
  A team admin features an accepted photo on its activity's Overview, or stops
  featuring it (#1033). An activity features up to ActivityPhoto.max_featured/0, so one
  more is refused until another stops. `check/2` is that rule.
  """

  import Ecto.Query

  alias App.Model.ActivityPhoto
  alias App.Repo
  alias Service.Format

  @doc """
  Pure. Whether the photo can be featured, on an activity that features `featured`
  already. `:ok`, also for one that is featured; `{:error, :waiting}` for a photo no team
  admin has accepted; or `{:error, :full}`.
  """
  def check(%ActivityPhoto{status: status}, _featured) when status != :accepted,
    do: {:error, :waiting}

  def check(%ActivityPhoto{featured_at: %DateTime{}}, _featured), do: :ok

  def check(%ActivityPhoto{}, featured) when is_integer(featured),
    do: if(featured < ActivityPhoto.max_featured(), do: :ok, else: {:error, :full})

  @doc """
  Features the photo, or with `false` stops featuring it. `{:ok, photo}`, or `check/2`'s
  error with nothing changed. The count and the change are one transaction, so two team
  admins never feature a third between them.
  """
  def call(%ActivityPhoto{} = photo, true, %DateTime{} = now) do
    Repo.transaction(fn ->
      # The row as it is now, through its team: the page may hold an older one.
      photo = Repo.get_by!(ActivityPhoto, id: photo.id, team_id: photo.team_id)

      case check(photo, count_featured(photo)) do
        :ok -> set(photo, photo.featured_at || now)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def call(%ActivityPhoto{} = photo, false, %DateTime{}) do
    photo = Repo.get_by!(ActivityPhoto, id: photo.id, team_id: photo.team_id)
    {:ok, set(photo, nil)}
  end

  defp set(photo, featured_at),
    do: photo |> Ecto.Changeset.change(featured_at: featured_at) |> Repo.update!()

  defp count_featured(%ActivityPhoto{team_id: team_id, activity_id: activity_id}) do
    ActivityPhoto
    |> where([p], p.team_id == ^team_id and p.activity_id == ^activity_id)
    |> where([p], p.status == :accepted and not is_nil(p.featured_at))
    |> Repo.aggregate(:count)
  end

  @doc "What the page says when `call/3` refuses."
  def error_text(:full) do
    Format.count(ActivityPhoto.max_featured(),
      one: "%d photo is featured already. Stop featuring it first.",
      many: "%d photos are featured already. Stop featuring one first."
    )
  end

  def error_text(:waiting), do: "Accept the photo first. Then feature it."
end
