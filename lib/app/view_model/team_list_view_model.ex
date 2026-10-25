defmodule App.ViewModel.TeamListViewModel do
  @moduledoc """
  The stat switch over a list of teams (#512, #513): which view of the teams to show. An
  unknown view falls back to the first, All, rather than a 404, since a list of teams
  has nothing to hide.
  """
  use App, :view_model

  @primary_key false
  embedded_schema do
    field :view, :string
  end

  @doc "The view `params` asks for, when it is one of `views`, else the first."
  def view(params, [default | _] = views) do
    changeset =
      %__MODULE__{view: default}
      |> cast(params, [:view])
      |> validate_required([:view])
      |> validate_inclusion(:view, views)

    case apply_action(changeset, :replace) do
      {:ok, %{view: view}} -> view
      {:error, _changeset} -> default
    end
  end

  @doc "The query params for a view, leaving out the default so the plain link opens All."
  def query_params(view, [default | _views]) when view == default, do: []
  def query_params(view, _views), do: [view: view]
end
