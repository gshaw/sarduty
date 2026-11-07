defmodule App.ViewModel.ActivityMembersFilterViewModel do
  @moduledoc """
  The filters on an activity's Members tab: a group by its local id (#895), a reply tile
  as `status`, and a name search as `q` (#920). A group that isn't the team's, or a status
  that doesn't fit the activity, filters nothing, so an old link still opens the tab.

  `status` is the tile's URL word: before the start `signed-up`, `cant-make-it`, or
  `no-reply`; from the start `attended`, `absent`, or `no-reply`. Each is one of D4H's
  statuses, `attending`, `absent`, or `requested`.
  """
  use App, :view_model

  @before_start %{
    "signed-up" => "attending",
    "cant-make-it" => "absent",
    "no-reply" => "requested"
  }
  @from_start %{"attended" => "attending", "absent" => "absent", "no-reply" => "requested"}

  @primary_key false
  embedded_schema do
    field :group, :integer
    field :status, :string
    field :q, :string
  end

  @doc """
  The filter from the URL's params, checked against the team's `{title, id}` groups and
  whether the activity has `started?`. Each part that doesn't fit is dropped on its own.
  """
  def validate(params, groups, started?) do
    # A field that doesn't cast, such as `group=abc`, stays out of the changes.
    filter = %__MODULE__{} |> cast(params, [:group, :status, :q]) |> apply_changes()

    %__MODULE__{
      group: if(Enum.any?(groups, fn {_title, id} -> id == filter.group end), do: filter.group),
      status: if(started? |> statuses() |> Map.has_key?(filter.status), do: filter.status),
      q: blank_to_nil(filter.q)
    }
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(q) do
    case String.trim(q) do
      "" -> nil
      q -> q
    end
  end

  defp statuses(true = _started?), do: @from_start
  defp statuses(false), do: @before_start

  @doc ~s(D4H's status for the filter's tile, or nil for All: "no-reply" is "requested".)
  def d4h_status(%__MODULE__{status: nil}), do: nil
  def d4h_status(%__MODULE__{status: status}), do: Map.merge(@before_start, @from_start)[status]

  @doc ~s(The tile's URL word for a D4H status: "attending" is "signed-up", then "attended".)
  def slug(d4h_status, started?) do
    started?
    |> statuses()
    |> Enum.find_value(fn {slug, status} -> status == d4h_status && slug end)
  end

  @doc "Whether anything but the tile filters: a group or a search."
  def narrowed?(%__MODULE__{group: group, q: q}), do: group != nil or q != nil

  @doc "The query params for `filter`, leaving out a filter that's off."
  def query_params(%__MODULE__{} = filter) do
    for key <- [:group, :status, :q], value = Map.get(filter, key), value != nil, do: {key, value}
  end
end
