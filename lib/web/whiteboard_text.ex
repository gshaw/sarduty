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
  alias App.Operation.SaveWhiteboardNote
  alias App.Repo
  alias Service.Format

  attr :note, WhiteboardNote, required: true
  attr :tag, :boolean, default: true, doc: "whether an Important note shows its tag"

  @doc "The note's text, its web addresses as links, with an Important tag after it."
  def note_text(assigns) do
    ~H"""
    <%= for segment <- segments(@note.text) do %>
      <.segment segment={segment} />
    <% end %>
    <.badge :if={@tag and @note.important} kind={:primary}>Important</.badge>
    """
  end

  attr :segment, :any, required: true

  # One line each, so no space creeps in between a link and the full stop after it.
  defp segment(%{segment: {:link, _href, _label}} = assigns) do
    ~H"""
    <.a external={true} href={elem(@segment, 1)}>{elem(@segment, 2)}</.a>
    """
  end

  defp segment(assigns), do: ~H"{@segment}"

  attr :note, WhiteboardNote, required: true
  attr :class, :any, default: nil

  @doc "The note's link, shown as its host, such as bcsara.com, unless the text holds it."
  def note_link(assigns) do
    ~H"""
    <span :if={@note.url && !link_in_text?(@note)} class={@class}>
      <.a external={true} href={@note.url}>{link_text(@note.url)}</.a>
    </span>
    """
  end

  # cspell:ignore sfsar (South Fraser SAR's web address, in the example below)
  # A web address in a note's text: one with http(s):// or www., or a bare host with a
  # path, like sfsar.ca/d4h. A bare host alone, like bcsara.com, stays text, so an email
  # address or "e.g." never turns into a link.
  @address ~r/(?<![\w@.\/-])(?:(?:https?:\/\/|www\.)[^\s<>"]+|[a-z0-9][a-z0-9-]*(?:\.[a-z0-9-]+)*\.[a-z]{2,}\/[^\s<>"]*)/i

  @doc """
  A note's text split into plain text and `{:link, href, label}` for each web address in
  it. Punctuation that ends a sentence stays text, not part of the link.
  """
  def segments(text) do
    {segments, rest_at} =
      @address
      |> Regex.scan(text, return: :index)
      |> Enum.flat_map_reduce(0, fn [{at, length}], from ->
        before = binary_part(text, from, at - from)
        {[before | link_segment(binary_part(text, at, length))], at + length}
      end)

    rest = binary_part(text, rest_at, byte_size(text) - rest_at)
    Enum.reject(segments ++ List.wrap(rest), &(&1 == ""))
  end

  defp link_segment(part) do
    [_all, address, tail] = Regex.run(~r/\A(.*?)([.,;:!?)'"]*)\z/s, part)
    href = if address =~ ~r{\Ahttps?://}i, do: address, else: "https://" <> address
    [{:link, href, address}, tail]
  end

  @doc "Whether the note's text already holds its link, so it needs no second one."
  def link_in_text?(%WhiteboardNote{url: nil}), do: false

  def link_in_text?(%WhiteboardNote{url: url, text: text}) do
    text
    |> segments()
    |> Enum.any?(fn
      {:link, href, _label} -> bare(href) == bare(url)
      _text -> false
    end)
  end

  defp bare(url) do
    url
    |> String.downcase()
    |> String.replace(~r{\A(https?://)?(www\.)?}, "")
    |> String.trim_trailing("/")
  end

  @doc ~s("BCSARA:", before an organization's note on the Dashboard.)
  def speaker(nil), do: "Your organization:"
  def speaker(org_name), do: "#{org_name}:"

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

  @doc "The Archive button's confirm."
  def archive_confirm, do: "Archive this note? It comes off the whiteboard for everyone."

  @doc """
  Archives the team's note with this local id, from a page's Archive button. The id comes
  from the page, so the note is found through the team. `:ok` or `{:error, text}`.
  """
  def archive(%Team{} = team, user, id),
    do: with_note(team, id, &SaveWhiteboardNote.archive(team, user, &1))

  @doc "Deletes the team's note with this local id, from the Archived list's Delete."
  def delete(%Team{} = team, user, id),
    do: with_note(team, id, &SaveWhiteboardNote.delete(team, user, &1))

  defp with_note(team, id, fun) do
    with {id, ""} <- id |> to_string() |> Integer.parse(),
         %WhiteboardNote{} = note <- WhiteboardNote.get_for_team(team, id),
         {:ok, _note} <- fun.(note) do
      :ok
    else
      {:error, text} when is_binary(text) -> {:error, text}
      _missing -> {:error, "The note is gone. Reload the page."}
    end
  end

  @doc "The short name of the team's organization in SAR Duty, or nil."
  def org_name(%Team{} = team) do
    case Repo.preload(team, :organization).organization do
      nil -> nil
      organization -> organization.short_name || organization.name
    end
  end
end
