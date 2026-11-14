defmodule Web.MemberPhoto do
  @moduledoc """
  Where a member's photo is, for an `<img>`: the team's `/members/:id/image` route, which
  a browser keeps for an hour. The path carries when SAR Duty last changed the photo
  (#1028), so one just saved shows at once, and a page of 85 members asks the team's
  records once an hour, not on each visit.

  Also what Add a photo and the check page share (#1029): where a waiting photo is,
  `place/1`, the square a photo is placed in, and the decline as the member reads it.
  """

  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: Web.Endpoint,
    router: Web.Router,
    statics: Web.static_paths()

  import Web.Components.Core, only: [button: 1]

  alias App.Model.Member
  alias App.Model.MemberPhoto
  alias App.Model.Team

  def path(%Team{} = team, %Member{photo_changed_at: nil} = member),
    do: ~p"/teams/#{team}/members/#{member.id}/image"

  def path(%Team{} = team, %Member{photo_changed_at: changed_at} = member),
    do: ~p"/teams/#{team}/members/#{member.id}/image?#{[v: DateTime.to_unix(changed_at)]}"

  @doc """
  A waiting photo's file, while SAR Duty keeps it: `:taken`, the photo as the member took
  it, `:cleaned`, the cleaned-up photo (#1031), or `:placed`, the square they placed.
  The path changes when the photo does.
  """
  def waiting_path(%Team{} = team, %MemberPhoto{} = photo, shape)
      when shape in [:taken, :cleaned, :placed] do
    version = DateTime.to_unix(photo.updated_at, :millisecond)
    ~p"/teams/#{team}/photos/members/#{photo.id}/file?#{[shape: shape, v: version]}"
  end

  @doc "The page where a team admin checks a photo a member added."
  def check_path(%Team{} = team, %MemberPhoto{id: id}),
    do: ~p"/teams/#{team}/photos/members/#{id}"

  @doc ~s(A decline as its member reads it: "Too dark".)
  def reason(%MemberPhoto{decline_reason: reason}), do: MemberPhoto.reason_text(reason)

  attr :id, :string, required: true, doc: "changes with the photo, so a new one starts again"
  attr :src, :string, required: true
  attr :width, :integer, required: true
  attr :height, :integer, required: true

  attr :placed, :any,
    default: {0, %{x: 0.5, y: 0.5, side: 1.0}},
    doc: "where it starts: the middle square, or where the member placed it"

  attr :label_id, :string, required: true, doc: "the element that names the square"
  attr :hint_id, :string, default: nil, doc: "the element that says what to do with it"

  @doc """
  The square the ID card shows, with the photo under the oval and the tools: Rotate, Zoom
  out, and Zoom in. The PhotoPlace hook (assets/js/photo_place.js) owns everything in
  here, so a change on the page leaves the photo where it was placed. It fills the
  form's `photo[turns]`, `photo[x]`, `photo[y]`, and `photo[side]`, which
  Service.MemberPhoto.placement/1 reads.
  """
  def place(assigns) do
    {turns, square} = assigns.placed
    assigns = assign(assigns, turns: turns, square: square)

    ~H"""
    <div
      id={"#{@id}-wrap"}
      phx-hook="PhotoPlace"
      phx-update="ignore"
      data-min-side={Service.MemberPhoto.min_share()}
    >
      <div
        id={@id}
        class="photo-place"
        tabindex="0"
        role="group"
        aria-labelledby={@label_id}
        aria-describedby={@hint_id}
        aria-keyshortcuts="ArrowLeft ArrowRight ArrowUp ArrowDown + -"
        data-photo-frame
      >
        <img src={@src} alt="" width={@width} height={@height} draggable="false" />
        <svg class="photo-place-oval" viewBox="0 0 100 100" aria-hidden="true">
          <ellipse class="photo-place-oval-edge" cx="50" cy="40" rx="21" ry="26" />
          <ellipse class="photo-place-oval-line" cx="50" cy="40" rx="21" ry="26" />
        </svg>
      </div>
      <div class="photo-place-tools">
        <.button id="photo-rotate" type="button" icon="rotate-cw-square" data-photo-tool="rotate">
          Rotate
        </.button>
        <.button id="photo-zoom-out" type="button" data-photo-tool="zoom-out">Zoom out</.button>
        <.button id="photo-zoom-in" type="button" data-photo-tool="zoom-in">Zoom in</.button>
      </div>
      <input type="hidden" name="photo[turns]" value={@turns} />
      <input type="hidden" name="photo[x]" value={@square.x} />
      <input type="hidden" name="photo[y]" value={@square.y} />
      <input type="hidden" name="photo[side]" value={@square.side} />
    </div>
    """
  end
end
