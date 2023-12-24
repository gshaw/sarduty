defmodule App.ViewModel.ActivityFilterViewModel do
  use App, :view_model

  alias App.Field
  alias App.Model.Activity
  alias App.Repo
  # alias App.Validate
  # alias App.ViewModel.ActivityFilterViewModel, as: VM

  @primary_key false
  embedded_schema do
    field :q, Field.TrimmedString
    field :activity, :string
    field :date, :string
    field :page, :integer
    field :limit, :integer
  end

  def activity_kinds, do: ["all", "exercise", "event", "incident"]
  def date_kinds, do: ["all", "past", "future"]
  def limits, do: [nil, 10, 25, 50, 100, 250, 500, 1000]

  defp build_new do
    %__MODULE__{
      date: "past",
      activity: "all"
    }
  end

  defp build_new_changeset(params), do: build_changeset(build_new(), params)

  defp build_changeset(data, params) do
    data
    |> cast(params, [:q, :date, :activity, :page, :limit])
    |> Field.truncate(:q, max_length: 100)
    |> validate_inclusion(:activity, activity_kinds())
    |> validate_inclusion(:date, date_kinds())
    |> validate_number(:page, greater_than_or_equal_to: 1)
    |> validate_number(:page, greater_than_or_equal_to: 1, less_than_or_equal_to: 1000)
  end

  def validate(params) do
    changeset = build_new_changeset(params)

    case apply_action(changeset, :replace) do
      {:ok, filter_options} -> {:ok, filter_options, changeset}
      {:error, _} = result -> result
    end
  end
end
