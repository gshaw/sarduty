defmodule Web.WhiteboardText do
  @moduledoc """
  The words for whiteboard notes (#515), so the Dashboard card and the Whiteboard page
  say the same thing.
  """

  use Phoenix.Component

  import Web.Components.A, only: [a: 1]
  import Web.Components.Core, only: [badge: 1]

  alias App.Model.Team
  alias App.Model.WhiteboardNote
  alias App.Repo
  alias Service.Format

  attr :note, WhiteboardNote, required: true

  @doc "The note's text, with an Important tag after it."
  def note_text(assigns) do
    ~H"""
    {@note.text}
    <.badge :if={@note.important} kind={:primary}>Important</.badge>
    """
  end

  attr :note, WhiteboardNote, required: true
  attr :class, :any, default: nil

  @doc "The note's link, shown as its host, such as bcsara.com."
  def note_link(assigns) do
    ~H"""
    <span :if={@note.url} class={@class}>
      <.a external={true} href={@note.url}>{link_text(@note.url)}</.a>
    </span>
    """
  end

  @doc ~s(A link's host without "www.", or the address of a mailto link.)
  def link_text("mailto:" <> address), do: address

  def link_text(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) and host != "" ->
        String.replace_prefix(host, "www.", "")

      _other ->
        url
    end
  end

  @doc ~s(The line under a note: "Posted Oct 22 · Until Oct 25 · From BCSARA".)
  def note_line(note, timezone, org_name, today) do
    [
      "Posted #{posted(note, timezone, today)}",
      until(note, timezone, today) && "Until #{until(note, timezone, today)}",
      note.owner_kind == :organization && from(org_name)
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" · ")
  end

  @doc "The day the note was posted, with its year when that isn't this year."
  def posted(%WhiteboardNote{d4h_created_at: nil}, _timezone, _today), do: nil

  def posted(note, timezone, today),
    do: note.d4h_created_at |> Service.Period.today(timezone) |> Format.day_in_year(today)

  @doc "The note's last day, or nil for one that never archives."
  def until(note, timezone, today) do
    case WhiteboardNote.last_day(note, timezone) do
      nil -> nil
      day -> Format.day_in_year(day, today)
    end
  end

  @doc ~s("From BCSARA", the team's organization's short name, on an organization's note.)
  def from(nil), do: "From your organization"
  def from(org_name), do: "From #{org_name}"

  @doc "The short name of the team's organization in SAR Duty, or nil."
  def org_name(%Team{} = team) do
    case Repo.preload(team, :organization).organization do
      nil -> nil
      organization -> organization.short_name || organization.name
    end
  end
end
