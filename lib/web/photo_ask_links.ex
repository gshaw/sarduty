defmodule Web.PhotoAskLinks do
  @moduledoc """
  The signed link an ask for a photo's email holds (#1030), to `/photos/:token`: Add a
  photo for the member asked, with no login, and nothing else. The token names one ask
  and is the only access. It works for 30 days, and only while the ask is open: adding a
  photo closes it.
  """
  alias App.Model.PhotoAsk
  alias App.Model.Team

  @salt "photo ask"
  @max_age 30 * 24 * 60 * 60

  def path(%PhotoAsk{id: id}), do: "/photos/" <> Phoenix.Token.sign(Web.Endpoint, @salt, id)

  def url(%PhotoAsk{} = ask), do: Web.Endpoint.url() <> path(ask)

  @doc """
  The open ask a token names, with its team, member, and who asked: `{:ok, ask}`.
  `:ended` for a link too old, an ask that closed, or a team that turned Photos off, and
  `:error` for a token that was never one.
  """
  def find_ask(token) when is_binary(token) do
    case Phoenix.Token.verify(Web.Endpoint, @salt, token, max_age: @max_age) do
      {:ok, id} when is_integer(id) -> open(PhotoAsk.get_open(id))
      {:error, :expired} -> :ended
      _error -> :error
    end
  end

  defp open(%PhotoAsk{team: team} = ask), do: if(Team.photos?(team), do: {:ok, ask}, else: :ended)
  defp open(nil), do: :ended
end
