defmodule App.ViewModel.AttendanceFilterViewModel do
  use App, :view_model

  import Ecto.Query

  alias App.Model.Activity
  alias App.Model.Attendance
  alias App.Repo

  @primary_key false
  embedded_schema do
    field :when, :string
    field :tag, :string
  end

  def when_kinds(member), do: build_member_year_options(member)
  def tag_kinds, do: ["all", "both", "primary", "secondary", "other"]

  defp activity_primary_hours_tag, do: Activity.primary_hours_tag()
  defp activity_secondary_hours_tag, do: Activity.secondary_hours_tag()

  defp build_member_year_options(member) do
    current = current_year()

    attendance_years =
      Attendance
      |> where([a], a.member_id == ^member.id)
      |> where([a], a.status == "attending")
      |> select([a], fragment("DISTINCT strftime('%Y', ?)", a.started_at))
      |> Repo.all()

    [current | attendance_years]
    |> Enum.uniq()
    |> Enum.sort(:desc)
  end

  def current_year, do: Date.utc_today().year |> Integer.to_string()

  def validate(params) do
    changeset = build_new_changeset(params)

    case apply_action(changeset, :replace) do
      {:ok, filter_options} -> {:ok, filter_options, changeset}
      {:error, _} = result -> result
    end
  end

  def build_filtered_content(member, filter_options) do
    Attendance
    |> Attendance.scope(member_id: member.id)
    |> scope(when: filter_options.when)
    |> scope(tag: filter_options.tag)
    |> order_by([r], desc: r.started_at)
    |> preload(:activity)
    |> Repo.all()
  end

  def calculate_total_hours(records) do
    total =
      records
      |> Enum.map(fn record ->
        Service.Convert.duration_to_hours(record.started_at, record.finished_at)
      end)
      |> Enum.sum()

    (total / 1.0)
    |> Float.round(1)
  end

  defp build_new do
    %__MODULE__{
      when: current_year(),
      tag: "all"
    }
  end

  defp build_new_changeset(params), do: build_changeset(build_new(), params)

  defp build_changeset(data, params) do
    data
    |> cast(params, [:when, :tag])
    |> validate_inclusion(:tag, tag_kinds())
  end

  defp scope(q, when: year) when is_binary(year),
    do: where(q, [r], fragment("strftime('%Y', ?) = ?", r.started_at, ^year))

  defp scope(q, tag: "all"), do: q

  defp scope(q, tag: "both") do
    q
    |> join(:left, [at], ac in assoc(at, :activity))
    |> where(
      [at, ac],
      ^activity_primary_hours_tag() in ac.tags or ^activity_secondary_hours_tag() in ac.tags
    )
  end

  defp scope(q, tag: "primary") do
    q
    |> join(:left, [at], ac in assoc(at, :activity))
    |> where([at, ac], ^activity_primary_hours_tag() in ac.tags)
  end

  defp scope(q, tag: "secondary") do
    q
    |> join(:left, [at], ac in assoc(at, :activity))
    |> where([at, ac], ^activity_secondary_hours_tag() in ac.tags)
  end

  defp scope(q, tag: "other") do
    q
    |> join(:left, [at], ac in assoc(at, :activity))
    |> where([at, ac], ^activity_primary_hours_tag() not in ac.tags)
    |> where([at, ac], ^activity_secondary_hours_tag() not in ac.tags)
  end
end
