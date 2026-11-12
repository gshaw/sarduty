defmodule App.Operation.CheckMemberPhoto do
  @moduledoc """
  Whether the team's records have a photo of the member (#1012), stored as
  `members.has_photo`, which an ID card needs. The one place that decides it: one image
  request, where a 200 is a photo and a 204 or 404 is none: D4H answers 204 with no body
  for a member with no photo (checked on South Fraser, 2026-11-11), Records 404. Any other
  answer keeps what was stored.

  Runs outside any transaction: nightly for each counted, current member
  (App.Worker.RefreshTeamDataWorker), and live before Issue, Replace, and Refresh ID card.
  """

  import Ecto.Query, only: [where: 3]

  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Model.MemberCard
  alias App.Model.PhotoAsk
  alias App.Model.Team
  alias App.Operation.RefreshMemberCard
  alias App.Repo

  require Logger

  @doc """
  Checks and stores, and returns the member with `has_photo` up to date. A request that
  got no answer, or an answer other than 200, 204, or 404, keeps what was stored. `d4h`
  defaults to the team's context. Expects the member with `:team` preloaded when no
  context is given.
  """
  def call(%Member{} = member, d4h \\ nil) do
    d4h = d4h || D4H.build_context_from_team(member.team)

    case D4H.fetch_member_image(d4h, member.d4h_member_id) do
      {:ok, _image, _filename} ->
        # A photo where there was none, added in the team's records, answers an ask for
        # one (#1030).
        if !member.has_photo, do: PhotoAsk.close_for_member(member, DateTime.utc_now())
        store(member, true)

      {:error, %{status: status}} when status in [204, 404] ->
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
  The nightly check, for a team with ID cards or Photos on (#1028): each counted, current
  member, card holders too, so Members without a photo lists a card already out with the
  placeholder. A card holder with a photo where there was none gets their card refreshed
  (RefreshMemberCard), so the placeholder leaves their phones the same night. Turning
  Photos on runs it too (SetTeamFeature.check_photos/2).
  """
  def check_team(%Team{id_cards_enabled: cards, photos_enabled: photos} = team, now)
      when cards or photos do
    d4h = D4H.build_context_from_team(team)

    found =
      Member
      |> where([m], m.team_id == ^team.id)
      |> Member.counted_query()
      |> Member.current_query(now)
      |> Repo.all()
      |> Enum.map(&{&1.has_photo, call(&1, d4h)})
      |> Enum.filter(fn {had_photo, member} -> not had_photo and member.has_photo end)
      |> Enum.map(fn {_had_photo, member} -> member.id end)

    team |> MemberCard.get_all_current(found) |> RefreshMemberCard.resend_cards(now)
    :ok
  end

  def check_team(%Team{}, _now), do: :ok

  @doc """
  Stores `has_photo` without a check. With `now`, for a photo SAR Duty just set or
  removed, it stores `photo_changed_at` too, which the photo's URL carries (#1028).
  """
  # By id, so a struct read before the last check still writes.
  def store(member, has_photo, now \\ nil)

  def store(%Member{id: id} = member, has_photo, nil) when is_boolean(has_photo) do
    Member |> where([m], m.id == ^id) |> Repo.update_all(set: [has_photo: has_photo])
    %{member | has_photo: has_photo}
  end

  def store(%Member{id: id} = member, has_photo, %DateTime{} = now) when is_boolean(has_photo) do
    changed_at = DateTime.truncate(now, :second)

    Member
    |> where([m], m.id == ^id)
    |> Repo.update_all(set: [has_photo: has_photo, photo_changed_at: changed_at])

    %{member | has_photo: has_photo, photo_changed_at: changed_at}
  end
end
