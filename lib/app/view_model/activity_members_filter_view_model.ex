defmodule App.ViewModel.ActivityMembersFilterViewModel do
  @moduledoc """
  The filter bar on an activity's Members tab (#895): a group, by its local id. A group
  that isn't the team's filters nothing, so an old link still opens the tab.
  """
  use App, :view_model

  @primary_key false
  embedded_schema do
    field :group, :integer
  end

  @doc "The filter from the URL's params, checked against the team's `{title, id}` groups."
  def validate(params, groups) do
    changeset = cast(%__MODULE__{}, params, [:group])

    filter =
      case apply_action(changeset, :replace) do
        {:ok, filter} -> filter
        {:error, _changeset} -> %__MODULE__{}
      end

    if Enum.any?(groups, fn {_title, id} -> id == filter.group end),
      do: filter,
      else: %__MODULE__{}
  end

  @doc "The query params for `filter`, leaving out a filter that's off."
  def query_params(%__MODULE__{group: nil}), do: []
  def query_params(%__MODULE__{group: group}), do: [group: group]
end
