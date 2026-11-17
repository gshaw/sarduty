defmodule Web.PhotoAskLinks do
  @moduledoc """
  The signed link an ask for a photo's email holds (#1030), to `/photos/:token`: Add a
  photo for the member asked, with no login, and nothing else. The token names one ask
  and is the only access. It works for 30 days, and only while the ask is open: adding a
  photo closes it.
  """
  alias App.Model.ActivityPhotoAsk
  alias App.Model.PhotoAsk
  alias App.Model.Team
  alias App.Operation.AskForActivityPhotos

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

  # An ask for an activity's photos (#1034) has its own link, to
  # `/photos/activities/:token`: Add photos for that activity as the member asked, with
  # no login, and nothing else. It works for 30 days too, as often as the member likes:
  # they may have more photos tomorrow.
  @activity_salt "activity photo ask"

  def activity_path(%ActivityPhotoAsk{id: id}),
    do: "/photos/activities/" <> Phoenix.Token.sign(Web.Endpoint, @activity_salt, id)

  def activity_url(%ActivityPhotoAsk{} = ask), do: Web.Endpoint.url() <> activity_path(ask)

  @doc """
  The ask a token names, with its team, activity, member, and who asked: `{:ok, ask}`.
  `:ended` for a link too old, an ask that is gone, or a member who may no longer add
  photos to the activity (AskForActivityPhotos.may_add?/2): the team turned Photos off,
  the activity stopped taking photos, or they no longer attended. `:error` for a token
  that was never one.
  """
  def find_activity_ask(token, %DateTime{} = now) when is_binary(token) do
    case Phoenix.Token.verify(Web.Endpoint, @activity_salt, token, max_age: @max_age) do
      {:ok, id} when is_integer(id) -> open_activity(ActivityPhotoAsk.get(id), now)
      {:error, :expired} -> :ended
      _error -> :error
    end
  end

  defp open_activity(%ActivityPhotoAsk{} = ask, now),
    do: if(AskForActivityPhotos.may_add?(ask, now), do: {:ok, ask}, else: :ended)

  defp open_activity(nil, _now), do: :ended
end
