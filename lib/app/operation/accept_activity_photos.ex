defmodule App.Operation.AcceptActivityPhotos do
  @moduledoc """
  A team admin accepts photos that wait on an activity (#1032), so everyone on the team
  sees them. Nothing reaches the team's records: activity photos are SAR Duty's own.
  """

  import Ecto.Query

  alias App.Accounts.User
  alias App.Model.Activity
  alias App.Model.ActivityPhoto
  alias App.Model.Team
  alias App.Repo

  @doc """
  Accepts the activity's waiting photos among `ids`, which come from the browser: only
  the team's, on this activity, and still waiting (ActivityPhoto.waiting_among/3).
  `{:ok, count}`, how many it accepted.
  """
  def call(%Team{} = team, %Activity{} = activity, ids, %User{} = user, %DateTime{} = now)
      when is_list(ids) do
    {count, _rows} =
      team
      |> ActivityPhoto.waiting_among(activity, ids)
      |> exclude(:order_by)
      |> Repo.update_all(
        set: [status: :accepted, accepted_by_user_id: user.id, accepted_at: now, updated_at: now]
      )

    {:ok, count}
  end
end
