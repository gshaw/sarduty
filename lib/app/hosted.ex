defmodule App.Hosted do
  @moduledoc """
  SAR Duty's own D4H-compatible store, for teams without D4H (docs/hosted-d4h.md).
  App.Hosted.API serves it in D4H's shape, and the D4H adapter talks to that API for a
  hosted team, so the sync, change sets, and every page work as they do for D4H.

  Every function takes the hosted team and finds rows through it, so one team's key
  never reaches another team's rows.
  """

  import Ecto.Query

  alias App.Hosted
  alias App.Repo

  @resources %{
    "members" => Hosted.Member,
    "tags" => Hosted.Tag,
    "events" => Hosted.Activity,
    "exercises" => Hosted.Activity,
    "incidents" => Hosted.Activity,
    "attendance" => Hosted.Attendance,
    "member-qualifications" => Hosted.Qualification,
    "member-qualification-awards" => Hosted.QualificationAward,
    "member-groups" => Hosted.Group,
    "member-group-memberships" => Hosted.GroupMembership
  }

  @activity_kinds %{"events" => "event", "exercises" => "exercise", "incidents" => "incident"}

  def resources, do: Map.keys(@resources)
  def activity_kind(resource), do: Map.get(@activity_kinds, resource)

  ## Teams and keys

  @doc """
  Creates a hosted team and its key. Returns `{:ok, team, key}`. The store keeps only the
  key's hash; the caller saves the key as the SAR Duty team's encrypted D4H key.
  """
  def create_team(attrs) do
    key = generate_key()

    team = %Hosted.Team{id: next_team_id(), access_key_hash: hash_key(key)}
    changeset = Hosted.Team.changeset(team, attrs)

    with {:ok, team} <- Repo.insert(changeset), do: {:ok, team, key}
  end

  # A hosted team's id is its d4h_team_id, which must never match a real D4H team's.
  # D4H's are small and fit in 32 bits, so hosted ones start near the top of that range.
  @first_team_id 2_000_000_000

  defp next_team_id do
    max = Repo.aggregate(Hosted.Team, :max, :id) || 0
    max(max, @first_team_id - 1) + 1
  end

  @doc "The hosted team a bearer key opens, or nil."
  def get_team_by_key(key) when is_binary(key) and key != "",
    do: Repo.get_by(Hosted.Team, access_key_hash: hash_key(key))

  def get_team_by_key(_key), do: nil

  @key_prefix "sdh_"

  @doc "Whether a key is one of ours, so the adapter can tell a hosted team's key."
  def key?(key), do: is_binary(key) and String.starts_with?(key, @key_prefix)

  defp generate_key do
    random = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    @key_prefix <> random
  end

  defp hash_key(key), do: :crypto.hash(:sha256, key)

  ## Reads

  @doc """
  One page of a list, as `{rows, total_size}`. `params` are D4H's query parameters
  with string keys: `page`, `size`, `sort`, `order`, and the filters each list takes.
  """
  def list(%Hosted.Team{} = team, resource, params) do
    query = resource |> base_query(team) |> filter(resource, params)
    total = Repo.aggregate(query, :count)
    {page, size} = paging(params)

    rows =
      query
      |> sort(params)
      |> limit(^size)
      |> offset(^(page * size))
      |> Repo.all()
      |> preload_for_json(resource)

    {rows, total}
  end

  @doc "One row by id, or nil."
  def get(%Hosted.Team{} = team, resource, id) do
    case resource |> base_query(team) |> where([r], r.id == ^id) |> Repo.one() do
      nil -> nil
      row -> row |> List.wrap() |> preload_for_json(resource) |> hd()
    end
  end

  defp base_query(resource, team) do
    query = @resources |> Map.fetch!(resource) |> where([r], r.hosted_team_id == ^team.id)

    case {resource, activity_kind(resource)} do
      {_, kind} when is_binary(kind) ->
        where(query, [a], a.kind == ^kind and is_nil(a.deleted_at))

      # D4H returns no attendance for a deleted activity.
      {"attendance", nil} ->
        join(query, :inner, [r], a in Hosted.Activity,
          on: a.id == r.activity_id and is_nil(a.deleted_at)
        )

      _other ->
        query
    end
  end

  defp filter(query, resource, params) do
    Enum.reduce(params, query, fn {name, value}, query ->
      filter_by(query, resource, name, value)
    end)
  end

  defp filter_by(query, _resource, "updated_after", value),
    do: where(query, [r], r.updated_at > ^time!(value))

  defp filter_by(query, "attendance", "activity_id", value),
    do: where(query, [r], r.activity_id == ^integer!(value))

  defp filter_by(query, resource, "member_id", value)
       when resource in ["attendance", "member-qualification-awards", "member-group-memberships"],
       do: where(query, [r], r.member_id == ^integer!(value))

  defp filter_by(query, "member-group-memberships", "group_id", value),
    do: where(query, [r], r.group_id == ^integer!(value))

  defp filter_by(query, "attendance", "starts_after", value),
    do: where(query, [r], r.starts_at >= ^time!(value))

  defp filter_by(query, "attendance", "starts_before", value),
    do: where(query, [r], r.starts_at < ^time!(value))

  defp filter_by(query, _resource, _name, _value), do: query

  @max_size 1000

  @doc "The page and size a list's params ask for: 250 a page by default, 1000 at most."
  def paging(params) do
    page = params |> Map.get("page", "0") |> integer!() |> max(0)
    size = params |> Map.get("size", "250") |> integer!() |> max(1) |> min(@max_size)
    {page, size}
  end

  defp sort(query, %{"sort" => "updatedAt"} = params),
    do: order_by(query, [r], [{^direction(params), r.updated_at}, {^direction(params), r.id}])

  defp sort(query, params), do: order_by(query, [r], [{^direction(params), r.id}])

  defp direction(%{"order" => "desc"}), do: :desc
  defp direction(_params), do: :asc

  # Attendance names its activity's kind, so the JSON can say Event or Incident.
  defp preload_for_json(rows, "attendance") do
    ids = rows |> Enum.map(& &1.activity_id) |> Enum.uniq()

    kinds =
      Hosted.Activity
      |> where([a], a.id in ^ids)
      |> select([a], {a.id, a.kind})
      |> Repo.all()
      |> Map.new()

    Enum.map(rows, &%{&1 | activity_kind: kinds[&1.activity_id]})
  end

  defp preload_for_json(rows, _resource), do: rows

  ## Writes

  @doc "Inserts a row of `resource` for the team. `{:ok, row}` or `{:error, reason}`."
  def create(%Hosted.Team{} = team, resource, attrs) do
    with {:ok, row} <- new_row(team, resource, attrs) do
      row
      |> changeset(resource, attrs)
      |> Repo.insert()
      |> preloaded(resource)
    end
  end

  @doc "Updates a team's row. `{:ok, row}`, `{:error, :not_found}`, or `{:error, changeset}`."
  def update(%Hosted.Team{} = team, resource, id, attrs) do
    case get(team, resource, id) do
      nil ->
        {:error, :not_found}

      row ->
        row
        |> changeset(resource, attrs)
        |> Ecto.Changeset.force_change(:updated_at, now())
        |> Repo.update()
        |> preloaded(resource)
    end
  end

  @doc """
  Deletes a team's row. Activities keep theirs, marked deleted, as D4H does. Members
  can't be deleted, only retired.
  """
  def delete(%Hosted.Team{} = team, resource, id) do
    case get(team, resource, id) do
      nil ->
        {:error, :not_found}

      %Hosted.Member{} ->
        {:error, :not_allowed}

      %Hosted.Tag{} = tag ->
        delete_unused_tag(team, tag)

      %Hosted.Activity{} = activity ->
        activity
        |> Ecto.Changeset.change(deleted_at: now(), updated_at: now())
        |> Repo.update()

      row ->
        Repo.delete(row)
    end
  end

  # Activities name tags by id, and letters count hours by the tag's title, so a tag in
  # use stays.
  defp delete_unused_tag(team, tag) do
    in_use =
      Hosted.Activity
      |> where([a], a.hosted_team_id == ^team.id)
      |> select([a], a.tag_ids)
      |> Repo.all()
      |> Enum.any?(&(tag.id in &1))

    if in_use,
      do: {:error, "The tag is on an activity. Remove it from them first."},
      else: Repo.delete(tag)
  end

  @doc "Sets an activity's tags to exactly these of the team's tag ids."
  def set_tags(%Hosted.Team{} = team, resource, id, tag_ids) do
    known =
      Hosted.Tag
      |> where([t], t.hosted_team_id == ^team.id and t.id in ^tag_ids)
      |> select([t], t.id)
      |> Repo.all()

    if length(Enum.uniq(tag_ids)) == length(known),
      do: update(team, resource, id, %{tag_ids: Enum.sort(known)}),
      else: {:error, "Unknown tag id."}
  end

  defp preloaded({:ok, row}, resource),
    do: {:ok, row |> List.wrap() |> preload_for_json(resource) |> hd()}

  defp preloaded(error, _resource), do: error

  # A new row with its team and the parents it names, each checked to be the team's.
  defp new_row(team, resource, attrs) do
    case activity_kind(resource) do
      nil -> new_child(team, resource, attrs)
      kind -> {:ok, %Hosted.Activity{hosted_team_id: team.id, kind: kind}}
    end
  end

  defp new_child(team, "attendance", attrs) do
    with {:ok, activity_id} <- parent(team, "activity", attrs),
         {:ok, member_id} <- parent(team, "member", attrs) do
      {:ok,
       %Hosted.Attendance{hosted_team_id: team.id, activity_id: activity_id, member_id: member_id}}
    end
  end

  defp new_child(team, "member-qualification-awards", attrs) do
    with {:ok, qualification_id} <- parent(team, "qualification", attrs),
         {:ok, member_id} <- parent(team, "member", attrs) do
      {:ok,
       %Hosted.QualificationAward{
         hosted_team_id: team.id,
         qualification_id: qualification_id,
         member_id: member_id
       }}
    end
  end

  defp new_child(team, "member-group-memberships", attrs) do
    with {:ok, group_id} <- parent(team, "group", attrs),
         {:ok, member_id} <- parent(team, "member", attrs) do
      {:ok,
       %Hosted.GroupMembership{hosted_team_id: team.id, group_id: group_id, member_id: member_id}}
    end
  end

  defp new_child(team, resource, _attrs) do
    {:ok, struct(Map.fetch!(@resources, resource), hosted_team_id: team.id)}
  end

  @parents %{
    "activity" => {:activity_id, Hosted.Activity},
    "member" => {:member_id, Hosted.Member},
    "qualification" => {:qualification_id, Hosted.Qualification},
    "group" => {:group_id, Hosted.Group}
  }

  defp parent(team, name, attrs) do
    {key, schema} = Map.fetch!(@parents, name)
    id = Map.get(attrs, key)

    found =
      is_integer(id) and
        schema
        |> where([r], r.id == ^id and r.hosted_team_id == ^team.id)
        |> then(fn q ->
          if schema == Hosted.Activity, do: where(q, [a], is_nil(a.deleted_at)), else: q
        end)
        |> Repo.exists?()

    if found, do: {:ok, id}, else: {:error, "Unknown #{name}."}
  end

  defp changeset(%Hosted.Activity{} = activity, _resource, attrs) do
    activity
    |> Hosted.Activity.changeset(attrs)
    |> put_reference()
  end

  # A membership has nothing to change; the parents are set on the struct.
  defp changeset(%Hosted.GroupMembership{} = membership, _resource, _attrs),
    do: Ecto.Changeset.change(membership)

  defp changeset(%schema{} = row, _resource, attrs), do: schema.changeset(row, attrs)

  # D4H numbers a team's activities when the team has auto ids on. Hosted teams always
  # do: the next number after the team's highest, five digits.
  defp put_reference(%Ecto.Changeset{data: %{id: nil}} = changeset) do
    case Ecto.Changeset.get_field(changeset, :reference) do
      blank when blank in [nil, ""] ->
        Ecto.Changeset.put_change(
          changeset,
          :reference,
          next_reference(changeset.data.hosted_team_id)
        )

      _given ->
        changeset
    end
  end

  defp put_reference(changeset), do: changeset

  defp next_reference(team_id) do
    count = Hosted.Activity |> where(hosted_team_id: ^team_id) |> Repo.aggregate(:count)
    count |> Kernel.+(1) |> Integer.to_string() |> String.pad_leading(5, "0")
  end

  defp now, do: DateTime.utc_now()

  defp integer!(value) when is_integer(value), do: value
  defp integer!(value) when is_binary(value), do: String.to_integer(value)

  defp time!(value) do
    {:ok, time, _offset} = DateTime.from_iso8601(value)
    time
  end
end
