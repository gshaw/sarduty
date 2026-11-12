defmodule App.Operation.AddActivityPhotos do
  @moduledoc """
  Someone adds photos to an activity (#1032): a member who attended it, or a team
  admin. Each photo waits until a team admin accepts it
  (App.Operation.AcceptActivityPhotos), a team admin's own too.

  On arrival each photo is read (Service.ActivityPhoto.prepare/1): location and camera
  data go, HEIC becomes JPEG, and three files are kept in the file store
  (App.Adapter.FileStore): the original at its full size, a copy to show, and one for
  tiles. The row names them and holds who added it, the send's caption, and whether the
  team may post it. Nothing reaches the team's records.

  `available?/1` is the one test of whether a team has activity photos at all, and
  `check/3` the one rule for who may add. Pages ask both, and `call/6` asks again.
  """

  import Ecto.Query

  alias App.Accounts.User
  alias App.Adapter.FileStore
  alias App.Model.Activity
  alias App.Model.ActivityPhoto
  alias App.Model.Attendance
  alias App.Model.Member
  alias App.Model.Team
  alias App.Repo
  alias Service.Format

  require Logger

  @doc """
  Whether the team has activity photos: Photos is on, and there is a file store. With
  no store, which is production until storage in Canada exists, there is no tab, no
  page, and no count.
  """
  def available?(%Team{} = team), do: Team.photos?(team) and FileStore.available?()

  @doc """
  Pure. Whether someone may add photos to the activity at `now`. `who` is
  `%{team_admin?:, attended?:}`, the second as Attendance.attended/2 counts it. `:ok`,
  or `{:error, reason}`: `:kind` for an incident or an activity with logged time
  (Activity.takes_photos?/1), `:deleted`, `:not_started`, or `:not_attended` for a
  member who did not attend. A team admin adds to any activity that takes photos, once
  it has started.
  """
  def check(activity, %{team_admin?: team_admin?, attended?: attended?}, %DateTime{} = now) do
    cond do
      not Activity.takes_photos?(activity) -> {:error, :kind}
      activity.deleted_at != nil -> {:error, :deleted}
      not Activity.started?(activity, now) -> {:error, :not_started}
      team_admin? or attended? -> :ok
      true -> {:error, :not_attended}
    end
  end

  @doc """
  Whether the person on a page may add photos to the activity now, for its Add photos
  button and its page. `who` is `%{team_admin?:, member:}`, the member they are or nil.
  The activity needs Activity.put_logged_minutes/1.
  """
  def may_add?(%Team{} = team, %Activity{} = activity, who, now),
    do: available?(team) and check(activity, attendance(activity, who, now), now) == :ok

  @doc """
  The activities the person may add photos to at `now`, newest first: what Photos' Add
  photos asks them to pick from (#1033). For a member, the exercises and events they
  attended; for a team admin, every one that has started. `who` is as may_add?/4 takes
  it. Each one passes `check/3`, the same rule the Add photos page asks, and has only
  its id, title, kind, and start.
  """
  def addable(%Team{} = team, who, %DateTime{} = now) do
    if available?(team) do
      attendance = %{team_admin?: who.team_admin?, attended?: not who.team_admin?}

      team
      |> started(who, now)
      |> Repo.all()
      |> Activity.put_logged_minutes(team.id)
      |> Enum.filter(&(check(&1, attendance, now) == :ok))
    else
      []
    end
  end

  # The team's exercises and events that have started: all of them for a team admin,
  # and for a member the ones they attended. Nobody else has any. A team admin's list
  # can run to thousands, so each comes with only what the rule and the box read.
  @listed [:id, :team_id, :d4h_activity_id, :title, :activity_kind, :started_at, :deleted_at]

  defp started(%Team{id: team_id}, who, now) do
    Activity
    |> where([a], a.team_id == ^team_id and a.activity_kind in ^Activity.photo_kinds())
    |> where([a], a.started_at <= ^now)
    |> Activity.not_deleted()
    |> attended_by(who, now)
    |> order_by([a], desc: a.started_at, desc: a.id)
    |> select([a], struct(a, ^@listed))
  end

  defp attended_by(query, %{team_admin?: true}, _now), do: query

  defp attended_by(query, %{member: %Member{id: member_id}}, now) do
    attended =
      Attendance
      |> where([r], r.member_id == ^member_id)
      |> Attendance.attended(now)
      |> select([r], r.activity_id)

    where(query, [a], a.id in subquery(attended))
  end

  defp attended_by(query, _nobody, _now), do: where(query, [a], false)

  defp attendance(activity, %{team_admin?: team_admin?} = who, now) do
    attended? =
      case who do
        %{member: %Member{} = member} -> Attendance.attended?(activity, member, now)
        _no_member -> false
      end

    %{team_admin?: team_admin?, attended?: attended?}
  end

  @doc """
  Adds the photos at `paths`, files the page already holds, to the activity. `who` is
  `%{user:, member:, team_admin?:}`, and `send` the send's `%{caption:, may_post:}`. The
  user is nil for a member adding through an ask's link, with no login (#1034).

  `{:ok, %{added:, unread:, unsaved:}}`, counts: the photos added, the files SAR Duty
  could not read, and the ones the file store did not take. `{:error, reason}` with
  nothing added: `check/3`'s reasons, `:off`, `:none` for no photo, `:too_many`, or
  `:caption` for one too long.
  """
  def call(%Team{} = team, %Activity{} = activity, %{user: user} = who, paths, send, now)
      when is_list(paths) and (is_struct(user, User) or is_nil(user)) do
    caption = caption(send[:caption])

    with :ok <- check_send(team, paths, caption),
         :ok <- check(activity, attendance(activity, who, now), now) do
      row = %{row(activity, who) | caption: caption, may_post: send[:may_post] == true}
      {:ok, paths |> Enum.map(&add(row, &1)) |> count()}
    end
  end

  # What every photo of the send has: its activity and who added it.
  defp row(activity, %{user: user, member: member}) do
    %ActivityPhoto{
      team_id: activity.team_id,
      activity_id: activity.id,
      member_id: member && member.id,
      added_by_user_id: user && user.id
    }
  end

  # The send itself: a team with activity photos, 1 to 20 photos, and a caption that fits.
  defp check_send(team, paths, caption) do
    cond do
      not available?(team) -> {:error, :off}
      paths == [] -> {:error, :none}
      length(paths) > Service.ActivityPhoto.max_photos() -> {:error, :too_many}
      too_long?(caption) -> {:error, :caption}
      true -> :ok
    end
  end

  defp too_long?(nil), do: false
  defp too_long?(caption), do: String.length(caption) > Service.ActivityPhoto.max_caption()

  defp caption(text) when is_binary(text) do
    case String.trim(text) do
      "" -> nil
      caption -> caption
    end
  end

  defp caption(_none), do: nil

  # One photo: its files first, then its row, so a row always has its files.
  defp add(row, path) do
    with {:ok, bytes} <- File.read(path),
         {:ok, files} <- Service.ActivityPhoto.prepare(bytes) do
      keep(
        %{row | file_token: ActivityPhoto.new_token(), width: files.width, height: files.height},
        files
      )
    else
      _unreadable -> :unread
    end
  end

  # A row that does not save takes its files away again.
  defp keep(photo, files) do
    with :ok <- put_files(photo, files),
         {:ok, _photo} <- Repo.insert(photo) do
      :added
    else
      error ->
        Logger.error("An activity photo did not save: #{inspect(error)}")
        for {_size, key} <- ActivityPhoto.keys(photo), do: FileStore.delete(key)
        :unsaved
    end
  end

  defp put_files(photo, files) do
    photo
    |> ActivityPhoto.keys()
    |> Enum.reduce_while(:ok, fn {size, key}, :ok ->
      case FileStore.put(key, Map.fetch!(files, size)) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp count(results) do
    counts = Enum.frequencies(results)
    %{added: counts[:added] || 0, unread: counts[:unread] || 0, unsaved: counts[:unsaved] || 0}
  end

  @doc """
  What the page says after `call/6`, as `{kind, text}`: "3 photos added. A team admin
  checks them.", and what was left out when some were not.
  """
  def result_text(%{added: added, unread: 0, unsaved: 0}) do
    checks = if added == 1, do: "A team admin checks it.", else: "A team admin checks them."
    {:info, "#{added_text(added)} #{checks}"}
  end

  def result_text(%{added: added, unread: unread, unsaved: unsaved}) do
    read =
      if unread > 0,
        do: [
          Format.count(unread,
            one: "SAR Duty cannot read %d photo. Select a JPEG.",
            many: "SAR Duty cannot read %d photos. Select JPEGs."
          )
        ],
        else: []

    saved =
      if unsaved > 0,
        do: [
          Format.count(unsaved,
            one: "%d photo did not save. Add it again.",
            many: "%d photos did not save. Add them again."
          )
        ],
        else: []

    {:error, Enum.join([added_text(added)] ++ read ++ saved, " ")}
  end

  defp added_text(0), do: "No photos added."

  defp added_text(added),
    do: Format.count(added, one: "%d photo added.", many: "%d photos added.")

  @doc "What the page says when `call/6` adds nothing."
  def error_text(:none), do: "Take a photo, or select some."

  def error_text(:too_many),
    do: "Add up to #{Service.ActivityPhoto.max_photos()} photos at a time."

  def error_text(:caption),
    do: "Keep the caption under #{Format.characters(Service.ActivityPhoto.max_caption())}."

  def error_text(:not_attended), do: "Only members who attended add photos to an activity."
  def error_text(:not_started), do: "Photos open when the activity starts."
  def error_text(_reason), do: "This activity does not take photos."
end
