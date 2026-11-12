defmodule App.Operation.DeleteActivityPhotos do
  @moduledoc """
  A team admin deletes photos that wait on an activity (#1032): each row and its three
  files, for good, through App.Operation.DeleteActivityPhoto. One whose files did not
  delete stays, to delete again.
  """

  alias App.Model.Activity
  alias App.Model.ActivityPhoto
  alias App.Model.Team
  alias App.Operation.DeleteActivityPhoto
  alias App.Repo

  @doc """
  Deletes the activity's waiting photos among `ids`, which come from the browser: only
  the team's, on this activity, and still waiting (ActivityPhoto.waiting_among/3).
  `{:ok, %{deleted:, kept:}}`, counts: `kept` are the ones the file store refused.
  """
  def call(%Team{} = team, %Activity{} = activity, ids) when is_list(ids) do
    results =
      team
      |> ActivityPhoto.waiting_among(activity, ids)
      |> Repo.all()
      |> Enum.map(&DeleteActivityPhoto.call(team, &1))

    deleted = Enum.count(results, &(&1 == :ok))
    {:ok, %{deleted: deleted, kept: length(results) - deleted}}
  end
end
