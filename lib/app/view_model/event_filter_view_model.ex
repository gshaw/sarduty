defmodule App.ViewModel.EventFilterViewModel do
  use App, :view_model

  alias App.Model.Event

  @primary_key false
  embedded_schema do
    field :kind, :string, default: "all"
    field :team, :string, default: "all"
  end

  def kinds, do: [{"All", "all"} | Enum.map(Event.kinds(), &{label(&1), Atom.to_string(&1)})]

  def teams(teams), do: [{"All", "all"} | Enum.map(teams, &{&1.name, Integer.to_string(&1.id)})]

  def label(:d4h_sync_round), do: "Sync round"
  def label(:d4h_refresh_run), do: "Nightly refresh"
  def label(:d4h_team_sync), do: "Team sync"
  def label(:d4h_team_refresh), do: "Team refresh"
  def label(:d4h_rate_limited), do: "D4H rate limit"

  def validate(params) do
    changeset =
      %__MODULE__{}
      |> cast(params, [:kind, :team])
      |> validate_inclusion(:kind, Enum.map(kinds(), &elem(&1, 1)))
      |> validate_format(:team, ~r/\A(all|\d+)\z/)

    case apply_action(changeset, :replace) do
      {:ok, filter} -> {:ok, filter, changeset}
      {:error, _} = result -> result
    end
  end

  @doc "The filter as `Event.get_recent/2` takes it."
  def to_query(%__MODULE__{kind: kind, team: team}) do
    %{
      kind: if(kind != "all", do: Enum.find(Event.kinds(), &(Atom.to_string(&1) == kind))),
      team_id: if(team != "all", do: String.to_integer(team))
    }
  end

  @doc "Query params for a path, leaving out the defaults."
  def to_params(%__MODULE__{} = filter) do
    filter |> Map.take([:kind, :team]) |> Enum.reject(fn {_key, value} -> value == "all" end)
  end
end
