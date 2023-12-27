defmodule App.ViewModel.MemberFilterViewModel do
  use App, :view_model

  alias App.Field

  @primary_key false
  embedded_schema do
    field :q, Field.TrimmedString
    field :year, :integer
    field :page, :integer
    field :limit, :integer
    field :sort, :string
  end

  def limits, do: [10, 25, 50, 100, 250, 500, 1000]

  def years, do: [2018, 2019, 2020, 2021, 2022, 2023, 2024]

  def sort_kinds,
    do: %{
      "Name" => "name",
      "Role" => "role",
      "ID ↓" => "id:desc",
      "ID ↑" => "id:asc",
      "Joined ↓" => "date:desc",
      "Joined ↑" => "date:asc"
    }

  defp build_new do
    %__MODULE__{
      year: 2023,
      limit: 100,
      sort: "name"
    }
  end

  defp build_new_changeset(params), do: build_changeset(build_new(), params)

  defp build_changeset(data, params) do
    data
    |> cast(params, [:q, :year, :page, :limit, :sort])
    |> Field.truncate(:q, max_length: 100)
    |> validate_inclusion(:sort, Map.values(sort_kinds()))
    |> validate_number(:year, greater_than_or_equal_to: 2018, less_than_or_equal_to: 2024)
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
