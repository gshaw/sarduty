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

  alias App.Model.ActivityPhoto
  alias App.Model.Member
  alias App.Model.Team

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

  @doc ~s(Who added the photo and when, under its tile: "Cameron Ruiz · Nov 4, 2026".)
  def added_text(%ActivityPhoto{} = photo, %Team{} = team, now) do
    [added_by(photo, team, now), Service.Format.date_short(photo.inserted_at, team.timezone)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  attr :id, :string, required: true
  attr :photo, ActivityPhoto, required: true
  attr :team, Team, required: true
  attr :alt, :string, required: true
  slot :inner_block, doc: "what sits on the photo's corner, such as a check box"

  @doc """
  The photo as a tile: the 600 px copy, 3 wide by 2 tall, which opens the copy to show
  in a new tab, so a page with boxes checked keeps them. Put it in a
  `.activity-photo-grid` list.
  """
  def tile(assigns) do
    ~H"""
    <div id={@id} class="activity-photo-tile">
      <a href={file_path(@team, @photo, :show)} target="_blank" rel="noopener">
        <img
          src={file_path(@team, @photo, :tile)}
          alt={@alt}
          width={@photo.width}
          height={@photo.height}
          loading="lazy"
          decoding="async"
        />
      </a>
      {render_slot(@inner_block)}
    </div>
    """
  end
end
