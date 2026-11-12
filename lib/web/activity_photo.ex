defmodule Web.ActivityPhoto do
  @moduledoc """
  What the pages that show an activity's photos share (#1032): where a photo's file is,
  who added it, and `tile/1`, the photo as a tile.
  """

  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: Web.Endpoint,
    router: Web.Router,
    statics: Web.static_paths()

  import Web.Components.Core, only: [icon: 1]

  alias App.Model.ActivityPhoto
  alias App.Model.Member
  alias App.Model.Team
  alias Service.Format

  @doc "The photo's own page (#1033), for an accepted photo."
  def page_path(%Team{} = team, %ActivityPhoto{id: id}), do: ~p"/teams/#{team}/photos/#{id}"

  @doc """
  One of the photo's files, for an `<img>` or a link: `:tile`, `:show`, or `:original`.
  The path carries when the photo last changed, so a browser that kept one file never
  shows it for another.
  """
  def file_path(%Team{} = team, %ActivityPhoto{} = photo, size)
      when size in [:tile, :show, :original] do
    version = DateTime.to_unix(photo.updated_at, :millisecond)
    ~p"/teams/#{team}/photos/#{photo.id}/file?#{[size: size, v: version]}"
  end

  @doc "An activity's Photos tab."
  def tab_path(%Team{} = team, activity_id),
    do: ~p"/teams/#{team}/activities/#{activity_id}/photos"

  @doc "Add photos, for an activity."
  def add_path(%Team{} = team, activity_id),
    do: ~p"/teams/#{team}/activities/#{activity_id}/photos/new"

  @doc """
  Who added the photo, as people read it: the member's name, or for a team admin with
  no member row, who their login is on the team (Member.name_for_user/3). Nil when
  neither is left. Needs `member` and `added_by_user` loaded.
  """
  def added_by(%ActivityPhoto{member: %Member{name: name}}, _team, _now), do: name

  def added_by(%ActivityPhoto{added_by_user: user}, %Team{} = team, now),
    do: Member.name_for_user(team, user, now)

  @doc """
  Who added the photo and when, under its tile: "Cameron Ruiz · Nov 4". The day alone,
  so it fits a tile's width: a photo is added within days of its activity, whose page
  says the year.
  """
  def added_text(%ActivityPhoto{} = photo, %Team{} = team, now) do
    [added_by(photo, team, now), Service.Format.month_day(photo.inserted_at, team.timezone)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  @doc """
  What the photo shows, for someone who cannot see it: its caption, or the activity it
  is from. Needs `activity` loaded when it has no caption.
  """
  def alt(%ActivityPhoto{caption: caption}) when is_binary(caption), do: caption
  def alt(%ActivityPhoto{activity: %{title: title}}), do: "Photo from #{title}"

  attr :id, :string, required: true
  attr :photo, ActivityPhoto, required: true
  attr :team, Team, required: true
  attr :alt, :string, required: true

  attr :stars, :boolean,
    default: false,
    doc: "whether its star count shows on its corner, from ActivityPhoto.put_stars/2"

  slot :inner_block, doc: "what sits on the photo's corner, such as a check box"

  @doc """
  The photo as a tile: the 600 px copy, 3 wide by 2 tall. An accepted photo opens its
  page (#1033). A waiting one has none, so it opens the copy to show in a new tab, and
  a page with boxes checked keeps them. With `stars`, its star count sits on its corner,
  the star filled when the person looking gave one. Put it in a `.activity-photo-grid`
  list.
  """
  def tile(assigns) do
    ~H"""
    <div id={@id} class="activity-photo-tile">
      <.link :if={@photo.status == :accepted} navigate={page_path(@team, @photo)}>
        <.tile_image photo={@photo} team={@team} alt={@alt} />
      </.link>
      <a :if={@photo.status != :accepted} href={file_path(@team, @photo, :show)} target="_blank">
        <.tile_image photo={@photo} team={@team} alt={@alt} />
      </a>
      <.star_count :if={@stars and @photo.status == :accepted} id={"#{@id}-stars"} photo={@photo} />
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :photo, ActivityPhoto, required: true
  attr :team, Team, required: true
  attr :alt, :string, required: true

  defp tile_image(assigns) do
    ~H"""
    <img
      src={file_path(@team, @photo, :tile)}
      alt={@alt}
      width={@photo.width}
      height={@photo.height}
      loading="lazy"
      decoding="async"
    />
    """
  end

  attr :id, :string, required: true
  attr :photo, ActivityPhoto, required: true

  # How many stars the photo has, on its tile's corner. Yours is a filled star.
  defp star_count(assigns) do
    ~H"""
    <span id={@id} class={["activity-photo-stars", @photo.starred && "is-starred"]}>
      <.icon name={if @photo.starred, do: "star-filled", else: "star"} size={:sm} />
      <span aria-hidden="true">{Format.number(@photo.stars)}</span>
      <span class="sr-only">{stars_text(@photo)}</span>
    </span>
    """
  end

  @doc ~s(A photo's stars in words, for a screen reader: "3 stars", then "You starred it.")
  def stars_text(%ActivityPhoto{stars: stars, starred: starred}) do
    count = Format.count(stars, one: "%d star", many: "%d stars")
    if starred, do: "#{count}. You starred it.", else: count
  end
end
