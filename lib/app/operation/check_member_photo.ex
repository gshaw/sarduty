defmodule App.Operation.CheckMemberPhoto do
  @moduledoc """
  Whether the team's records have a photo of the member (#1012), stored as
  `members.has_photo`, which an ID card needs. The one place that decides it: one image
  request, where a 200 is a photo and a 404 is none. D4H and Records both answer 404 for
  a member with no photo. Any other answer keeps what was stored.

  Runs outside any transaction: nightly for each counted, current member
  (App.Worker.RefreshTeamDataWorker), and live before Issue, Replace, and Refresh ID card.
  """

  import Ecto.Query, only: [where: 3]

  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Model.Team
  alias App.Repo

  require Logger

  @doc """
  Checks and stores, and returns the member with `has_photo` up to date. A request that
  got no answer, or an answer other than 200 or 404, keeps what was stored. `d4h` defaults to the team's context.
  Expects the member with `:team` preloaded when no context is given.
  """
  def call(%Member{} = member, d4h \\ nil) do
    d4h = d4h || D4H.build_context_from_team(member.team)

    case D4H.fetch_member_image(d4h, member.d4h_member_id) do
      {:ok, _image, _filename} ->
        store(member, true)

      {:error, %{status: 404}} ->
        store(member, false)

      # A rate limit or an outage says nothing about the photo.
      {:error, response} ->
        Logger.warning("photo check failed: HTTP #{response.status}")
        member
    end
  rescue
    error in Req.TransportError ->
      Logger.warning("photo check failed: #{Exception.message(error)}")
      member
  end

  @doc """
  The nightly check, for a team with ID cards on: each counted, current member, card
  holders too, so Members without a photo lists a card already out with the placeholder.
  """
  def check_team(%Team{id_cards_enabled: true} = team, now) do
    d4h = D4H.build_context_from_team(team)

    Member
    |> where([m], m.team_id == ^team.id)
    |> Member.counted_query()
    |> Member.current_query(now)
    |> Repo.all()
    |> Enum.each(&call(&1, d4h))
  end

  def check_team(%Team{}, _now), do: :ok

  @doc "Stores `has_photo` without a check, for a photo SAR Duty just set or removed."
  # By id, so a struct read before the last check still writes.
  def store(%Member{id: id} = member, has_photo) when is_boolean(has_photo) do
    Member |> where([m], m.id == ^id) |> Repo.update_all(set: [has_photo: has_photo])
    %{member | has_photo: has_photo}
  end
end
