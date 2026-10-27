defmodule App.Operation.FindPlace do
  @moduledoc """
  Finds an activity's place as a team admin types it (#610): first the places the team's
  own activities used, then places from Mapbox's Search Box, nearest the team first, and
  the text and coordinate of the one they pick. Only reads. A Mapbox failure lists
  nothing, so the field still takes what was typed.

  The team's own places cost nothing, so they show before any typing. Mapbox bills a
  session, so it is asked only once a person types. The team's location bookmarks (#614)
  name its places, and typing finds a bookmark by its title even when no activity used it.
  """

  alias App.Adapter.Mapbox
  alias App.Model.Activity
  alias App.Model.Coordinate
  alias App.Model.LocationBookmark
  alias App.Model.Team

  @past_years 2
  @past_shown 3
  @same_spot_m 150

  @doc """
  The places the team's activities used in the last #{@past_years} years, up to `now`, in
  rank/1 order, named by the team's bookmarks (name/2). Activities still to come are left
  out, so a place's last use is past.
  """
  def past_places(%Team{} = team, %DateTime{} = now) do
    team
    |> Activity.places(DateTime.add(now, -@past_years * 365, :day), now)
    |> rank()
    |> name(LocationBookmark.get_all(team))
  end

  @doc """
  One place per spot, most used first, then most recently used. Text typed differently
  for pins within #{@same_spot_m} m is one spot, since the same hall gets typed as 17499
  and 17543 20 Ave. A spot's text and pin are those of its text used most.
  """
  def rank(rows) do
    rows
    |> Enum.group_by(&String.downcase(&1.address))
    |> Enum.map(fn {_text, rows} -> build_past(rows) end)
    |> most_used()
    |> Enum.reduce([], &add_to_spot/2)
    |> most_used()
  end

  defp most_used(places), do: Enum.sort_by(places, &{-&1.count, -DateTime.to_unix(&1.last_at)})

  defp build_past(rows) do
    latest = Enum.max_by(rows, &DateTime.to_unix(&1.started_at))
    pin = latest |> Activity.pin() |> Coordinate.build()

    %{
      text: String.slice(latest.address, 0, 100),
      pin: pin,
      coordinate: pin && Coordinate.to_string(pin, 5),
      count: length(rows),
      last_at: latest.started_at,
      name: nil
    }
  end

  # Spots are built most used first, so a spot keeps the text used most.
  defp add_to_spot(place, spots) do
    case Enum.find_index(spots, &near?(&1.pin, place.pin)) do
      nil ->
        [place | spots]

      i ->
        List.update_at(spots, i, fn spot ->
          %{
            spot
            | count: spot.count + place.count,
              last_at: Enum.max([spot.last_at, place.last_at], DateTime)
          }
        end)
    end
  end

  @doc """
  Names each place with the nearest bookmark within #{@same_spot_m} m: its title, without
  a leading `!`. A bookmark names the most used place near it only, and keeps that
  place's text and pin. The bookmarks that name no place follow, A to Z, with no uses,
  so typing finds them by title.
  """
  def name(places, bookmarks) do
    bookmarks = Enum.map(bookmarks, &build_bookmark/1)

    {named, unused} =
      Enum.map_reduce(places, bookmarks, fn place, unused ->
        case nearest(unused, place.pin) do
          nil -> {place, unused}
          bookmark -> {%{place | name: bookmark.name}, List.delete(unused, bookmark)}
        end
      end)

    named ++ Enum.sort_by(unused, &String.downcase(&1.name))
  end

  defp build_bookmark(%LocationBookmark{} = bookmark) do
    pin = bookmark |> Activity.pin() |> Coordinate.build()
    name = LocationBookmark.name(bookmark)
    address = String.slice(bookmark.address || "", 0, 100)

    %{
      text: if(address == "", do: name, else: address),
      pin: pin,
      coordinate: pin && Coordinate.to_string(pin, 5),
      count: 0,
      last_at: nil,
      name: name
    }
  end

  defp nearest(bookmarks, pin) do
    bookmarks
    |> Enum.filter(&near?(&1.pin, pin))
    |> Enum.min_by(&distance_squared(&1.pin, pin), fn -> nil end)
  end

  defp near?({_, _} = pin, {_, _} = other),
    do: distance_squared(pin, other) <= @same_spot_m * @same_spot_m

  defp near?(_pin, _other), do: false

  # Flat-earth distance in metres, squared, close enough at this scale.
  defp distance_squared({lat1, lng1}, {lat2, lng2}) do
    dy = (lat2 - lat1) * 111_320
    dx = (lng2 - lng1) * 111_320 * :math.cos(lat1 * :math.pi() / 180)
    dx * dx + dy * dy
  end

  @doc """
  The team's places to show for `text`: before any typing, the #{@past_shown} most used
  that were used more than once; after, the #{@past_shown} whose name and text hold every
  word typed.
  """
  def match_past(places, text) do
    case (text || "") |> String.downcase() |> String.split() do
      [] -> places |> Enum.filter(&(&1.count > 1)) |> Enum.take(@past_shown)
      words -> places |> Enum.filter(&holds_all?(&1, words)) |> Enum.take(@past_shown)
    end
  end

  defp holds_all?(place, words) do
    text = String.downcase("#{place.name} #{place.text}")
    Enum.all?(words, &String.contains?(text, &1))
  end

  @doc "A new search session's token. One session is typing that ends in one pick."
  def new_session, do: Ecto.UUID.generate()

  @doc "Up to 5 places matching `text`, or none for short text or a Mapbox failure."
  def suggest(%Team{} = team, text, session_token) do
    text = String.trim(text || "")

    with true <- String.length(text) >= 3,
         {:ok, places} <-
           Mapbox.suggest_places(Mapbox.build_context(), text, session_token, near(team)) do
      Enum.reject(places, &is_nil(&1.id))
    else
      _short_or_failed -> []
    end
  end

  @doc "`{:ok, %{place: text, coordinate: {lat, lng}}}` for a pick, or `:error`."
  def pick(id, session_token) do
    case Mapbox.retrieve_place(Mapbox.build_context(), id, session_token) do
      {:ok, %{coordinate: {_lat, _lng} = coordinate} = place} ->
        {:ok, %{place: place_text(place), coordinate: coordinate}}

      _failed ->
        :error
    end
  end

  defp near(%Team{lat: lat, lng: lng}) when is_number(lat) and is_number(lng), do: {lat, lng}
  defp near(_team), do: nil

  @doc """
  The text for the form's place: the name, then the address without the country, at
  most 100 characters, as D4H takes. An address's name is its first line, so it isn't
  said twice.
  """
  def place_text(%{name: name, address: address, country: country}) do
    [name | String.split(address || "", ", ")]
    |> Enum.reject(&(&1 in [nil, "", country]))
    |> Enum.uniq()
    |> Enum.join(", ")
    |> String.slice(0, 100)
  end
end
