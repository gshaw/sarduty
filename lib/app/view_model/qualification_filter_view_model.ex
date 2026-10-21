defmodule App.ViewModel.QualificationFilterViewModel do
  @moduledoc """
  The filters on the qualifications list and one qualification's awards (#367): a view,
  a search, a group, and how far ahead the expiring view looks.
  """
  use App, :view_model

  alias App.Field
  alias App.Operation.BuildGroupRulePreview

  @primary_key false
  embedded_schema do
    field :view, :string
    field :q, Field.TrimmedString
    field :group, :integer
    field :within, :integer
  end

  @within_days [30, 60, 90, 180]

  @doc "The expiring view's time frames. The home page's item links with the default."
  def within_kinds, do: Enum.map(@within_days, &{Service.Format.days(&1), "#{&1}"})

  def default_within, do: BuildGroupRulePreview.expiring_days()

  @doc "Checks `params` against the page's views, the first being its default."
  def validate(params, [default_view | _] = views) do
    changeset =
      %__MODULE__{view: default_view, within: default_within()}
      |> cast(params, [:view, :q, :group, :within])
      |> Field.truncate(:q, max_length: 100)
      |> validate_required([:view, :within])
      |> validate_inclusion(:view, views)
      |> validate_inclusion(:within, @within_days)

    case apply_action(changeset, :replace) do
      {:ok, filter_options} -> {:ok, filter_options, changeset}
      {:error, _} = result -> result
    end
  end

  @doc """
  The query params for `filter_options`, leaving out each one at its default so the
  plain link opens the same list.
  """
  def query_params(%__MODULE__{} = filter_options, default_view) do
    Enum.reject(
      [
        view: filter_options.view,
        q: filter_options.q,
        group: filter_options.group,
        within: filter_options.within
      ],
      fn {key, value} ->
        value in [nil, ""] or (key == :view and value == default_view) or
          (key == :within and to_string(value) == to_string(default_within()))
      end
    )
  end
end
