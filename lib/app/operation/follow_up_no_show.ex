defmodule App.Operation.FollowUpNoShow do
  alias App.Accounts.User
  alias App.Model.NoShow
  alias App.Model.Team

  @doc """
  Marks a no-show followed up with what they heard, `{:note, note}` with a blank note
  kept as nil, or not followed up with `nil`. `{:ok, no_show}`, or `:error` for another
  team's.
  """
  def call(%Team{} = team, no_show_id, followed_up, %User{} = user, now) do
    case NoShow.set_followed_up(team, no_show_id, clean(followed_up), user, now) do
      nil -> :error
      no_show -> {:ok, no_show}
    end
  end

  @doc "Deletes a no-show that wasn't one (#650). `:ok`, or `:error` for another team's."
  def remove(%Team{} = team, no_show_id) do
    case NoShow.remove(team, no_show_id) do
      nil -> :error
      _no_show -> :ok
    end
  end

  @max_note 200

  defp clean({:note, note}) do
    case note |> to_string() |> String.trim() |> String.slice(0, @max_note) do
      "" -> {:note, nil}
      note -> {:note, note}
    end
  end

  defp clean(nil), do: nil
end
