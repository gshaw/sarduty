defmodule App.Operation.RefreshD4HData.CheckMemberPhotos do
  @moduledoc """
  Records whether D4H has a photo for each current member (#205), for the dashboard's
  "members missing details". D4H's member record doesn't say, so this asks the image
  endpoint with a HEAD request per member, 4 at a time.

  `:unchecked` asks only for members never checked, so the sync every 10 minutes asks
  about new members and nobody else. `:current` asks for every current member, so the
  nightly refresh sees a photo added or removed in D4H within a day.
  """
  import Ecto.Query

  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Repo

  require Logger

  @concurrency 4

  def call(d4h, team, scope, now \\ DateTime.utc_now()) do
    results = team.id |> members_to_check(scope, now) |> Repo.all() |> ask(d4h)

    # updated_at stays: a photo isn't a D4H change the nightly count of missed rows wants.
    for {has_photo, rows} <- Enum.group_by(results, &elem(&1, 1)) do
      ids = Enum.map(rows, &elem(&1, 0))
      Member |> where([m], m.id in ^ids) |> Repo.update_all(set: [has_photo: has_photo])
    end

    Logger.info("Checked #{length(results)} member photos for team #{team.id}")
    length(results)
  end

  # `{member_id, has_photo}` for each member D4H answered for. One that errs or times out
  # keeps what it had, and the next check tries again.
  defp ask(members, d4h) do
    members
    |> Task.async_stream(&{&1.id, D4H.member_has_image(d4h, &1.d4h_member_id)},
      max_concurrency: @concurrency,
      timeout: :timer.seconds(30),
      on_timeout: :kill_task
    )
    |> Enum.flat_map(fn
      {:ok, {id, {:ok, has_photo}}} -> [{id, has_photo}]
      _error_or_timeout -> []
    end)
  end

  defp members_to_check(team_id, scope, now) do
    query =
      Member
      |> where([m], m.team_id == ^team_id)
      |> where([m], is_nil(m.left_at) or m.left_at > ^now)
      |> where([m], is_nil(m.d4h_status) or m.d4h_status != "RETIRED")
      |> select([m], %{id: m.id, d4h_member_id: m.d4h_member_id})

    case scope do
      :unchecked -> where(query, [m], is_nil(m.has_photo))
      :current -> query
    end
  end

  @doc "Records what fetching a member's photo found, so a card's fetch keeps it current."
  def record(%Member{} = member, has_photo) when is_boolean(has_photo) do
    if member.has_photo != has_photo do
      Member |> where([m], m.id == ^member.id) |> Repo.update_all(set: [has_photo: has_photo])
    end

    :ok
  end
end
