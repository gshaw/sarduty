defmodule Web.MemberPhotoFormLive do
  use Web, :live_view_narrow_layout

  alias App.Model.Member
  alias App.Model.Team
  alias App.Operation.SetMemberPhoto
  alias Service.MemberPhoto
  alias Web.PhotoCollectionLive

  # Add a photo (#1028), /teams/:subdomain/photos/members/new: a team admin takes or
  # selects a member's photo, places the face in the oval, and saves it. One task with a
  # phone in hand, so a narrow page. `?member=<id>` names the member; with none, a Member
  # box lists the current members.
  #
  # The photo uploads the moment it is picked. Service.MemberPhoto reads it, HEIC too,
  # into a JPEG the page shows for placing, since a browser cannot show every photo a
  # phone takes. That copy lives in this page's memory alone: SAR Duty keeps no photo.
  # The PhotoPlace hook (assets/js/photo_place.js) moves it and fills in where it was
  # placed; Save photo cuts that square and sends it (SetMemberPhoto).
  @rules [
    "Head and shoulders, facing the camera",
    "A plain, light wall behind you",
    "Daylight or a bright room",
    "No hat or sunglasses. Glasses are fine."
  ]

  # The drawn examples in priv/static/images, so the guide shows nobody real.
  @bad [
    {"photo-guide-sunglasses.svg", "Sunglasses"},
    {"photo-guide-hat.svg", "Hat or helmet"},
    {"photo-guide-dark.svg", "Too dark"},
    {"photo-guide-someone-else.svg", "Someone else in it"},
    {"photo-guide-busy-background.svg", "Busy background"}
  ]

  def mount(params, _session, socket) do
    team = socket.assigns.current_team
    if !Team.photos?(team), do: raise(Web.Status.NotFound)
    member = if id = params["member"], do: Member.find!(team, id)

    socket
    |> assign(page_title: "Add a photo", member: member, photo: nil, photo_count: 0)
    |> assign(members: if(member, do: nil, else: members(team)))
    |> assign(back: back(team, member))
    |> allow_upload(:photo,
      accept: ~w(image/*),
      max_entries: 1,
      max_file_size: MemberPhoto.max_bytes(),
      auto_upload: true,
      progress: &handle_progress/3
    )
    |> then(&{:ok, &1})
  end

  # Where Cancel goes: the member's ID Card tab, where saving lands too, or Photos when
  # the page opened with no member.
  defp back(team, nil), do: PhotoCollectionLive.view_path(team, :members)
  defp back(team, member), do: ~p"/teams/#{team}/members/#{member.id}/card"

  # The Member box's options, with no member in the URL.
  defp members(team) do
    for member <- Member.get_all_counted(team, DateTime.utc_now()),
        do: {member.name, to_string(member.id)}
  end

  # The photo has uploaded: read it into the copy the page places.
  defp handle_progress(:photo, %{done?: true} = entry, socket) do
    bytes = consume_uploaded_entry(socket, entry, fn %{path: path} -> {:ok, File.read!(path)} end)

    case MemberPhoto.prepare(bytes) do
      {:ok, photo} ->
        photo = Map.put(photo, :src, "data:image/jpeg;base64," <> Base.encode64(photo.bytes))
        {:noreply, socket |> assign(photo: photo) |> update(:photo_count, &(&1 + 1))}

      {:error, text} ->
        {:noreply, put_flash(socket, :error, text)}
    end
  end

  defp handle_progress(:photo, _entry, socket), do: {:noreply, socket}

  def handle_event("validate", params, socket),
    do: {:noreply, socket |> pick_member(params) |> refuse_upload()}

  def handle_event("take-another", _params, socket), do: {:noreply, assign(socket, photo: nil)}

  def handle_event("save", params, socket) do
    socket = pick_member(socket, params)
    %{current_team: team, current_user: user, member: member, photo: photo} = socket.assigns

    cond do
      is_nil(member) -> {:noreply, put_flash(socket, :error, "Select a member.")}
      is_nil(photo) -> {:noreply, put_flash(socket, :error, "Take a photo, or select one.")}
      true -> {:noreply, save(socket, team, member, photo, params["photo"] || %{}, user)}
    end
  end

  defp save(socket, team, member, photo, placed, user) do
    {turns, square} = MemberPhoto.placement(placed)

    with {:ok, jpeg} <- MemberPhoto.place(photo.bytes, turns, square),
         :ok <- SetMemberPhoto.call(team, member, jpeg, user, DateTime.utc_now()) do
      socket
      |> put_flash(:info, "Photo saved.")
      |> push_navigate(to: ~p"/teams/#{team}/members/#{member.id}/card")
    else
      {:error, text} when is_binary(text) ->
        put_flash(socket, :error, text)

      {:error, _reason} ->
        put_flash(socket, :error, "SAR Duty cannot read this photo. Take another, or select one.")
    end
  end

  # The Member box picks who the photo is of. With a member in the URL there is no box.
  defp pick_member(%{assigns: %{members: nil}} = socket, _params), do: socket

  defp pick_member(socket, %{"member_id" => id}) do
    known? = Enum.any?(socket.assigns.members, fn {_name, value} -> value == id end)
    assign(socket, member: if(known?, do: Member.find!(socket.assigns.current_team, id)))
  end

  defp pick_member(socket, _params), do: socket

  # A file the upload will not take, such as one over 10 MB: say so and drop it, so the
  # buttons are ready for another.
  defp refuse_upload(socket) do
    upload = socket.assigns.uploads.photo

    case Enum.find(upload.entries, &(!&1.valid?)) do
      nil ->
        socket

      entry ->
        error = upload |> upload_errors(entry) |> List.first()

        socket
        |> cancel_upload(:photo, entry.ref)
        |> put_flash(:error, upload_error(error, upload, "a photo"))
    end
  end

  def render(assigns) do
    assigns = assign(assigns, rules: @rules, bad: @bad)

    ~H"""
    <.breadcrumbs>
      <:item label="Photos" path={PhotoCollectionLive.view_path(@current_team, :members)} />
      <:item label="Add a photo" />
    </.breadcrumbs>
    <h1 class="title">Add a photo</h1>
    <p id="photo-lead" class="lead">{lead(@member)}</p>

    <form id="photo-form" phx-change="validate" phx-submit="save">
      <.input
        :if={@members}
        type="combobox"
        id="photo-member"
        name="member_id"
        label="Member"
        prompt="Select a member"
        options={@members}
        value={@member && to_string(@member.id)}
      />

      <div :if={!@photo} id="photo-pick" phx-hook="PhotoPick">
        <h2 class="subheading">What works</h2>
        <div id="photo-guide-good" class="photo-guide">
          <span class="photo-guide-example">
            <img src={~p"/images/photo-guide-good.svg"} alt="" width="112" height="112" />
            <span class="photo-guide-mark is-good"><.icon name="check" size={:sm} /></span>
          </span>
          <ul>
            <li :for={rule <- @rules}>{rule}</li>
          </ul>
        </div>

        <h2 class="subheading">What does not</h2>
        <ul id="photo-guide-bad" class="photo-guide-bad">
          <li :for={{file, text} <- @bad}>
            <span class="photo-guide-example block">
              <img src={~p"/images/#{file}"} alt="" width="112" height="112" />
              <span class="photo-guide-mark is-bad"><.icon name="x" size={:sm} /></span>
            </span>
            {text}
          </li>
        </ul>

        <.form_actions>
          <.button id="photo-take" type="button" variant={:success} data-photo-pick="camera">
            Take a photo
          </.button>
          <.button id="photo-select" type="button" data-photo-pick="file">Select a photo</.button>
          <.button id="photo-cancel" navigate={@back}>Cancel</.button>
        </.form_actions>
        <.spinner :if={@uploads.photo.entries != []} id="photo-reading" class="block mt-4">
          Reading the photo…
        </.spinner>
        <%!-- Both buttons open this one input: Take a photo with the camera asked for
          (capture="user"), Select a photo without. --%>
        <.live_file_input upload={@uploads.photo} class="hidden" />
      </div>

      <div :if={@photo} id="photo-placed">
        <span id="photo-place-label" class="label block">Photo</span>
        <p id="photo-place-hint" class="hint mb-2">Move or zoom it so the face fills the oval.</p>
        <%!-- The hook owns everything in here, so a change on the page leaves the photo
          where it was placed. A new photo is a new element. --%>
        <div
          id={"photo-place-wrap-#{@photo_count}"}
          phx-hook="PhotoPlace"
          phx-update="ignore"
          data-min-side={MemberPhoto.min_share()}
        >
          <div
            id={"photo-place-#{@photo_count}"}
            class="photo-place"
            tabindex="0"
            role="group"
            aria-labelledby="photo-place-label"
            aria-describedby="photo-place-hint"
            aria-keyshortcuts="ArrowLeft ArrowRight ArrowUp ArrowDown + -"
            data-photo-frame
          >
            <img src={@photo.src} alt="" width={@photo.width} height={@photo.height} draggable="false" />
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
          <input type="hidden" name="photo[turns]" value="0" />
          <input type="hidden" name="photo[x]" value="0.5" />
          <input type="hidden" name="photo[y]" value="0.5" />
          <input type="hidden" name="photo[side]" value="1" />
        </div>

        <.form_actions>
          <.button id="photo-save" variant={:success} phx-disable-with="Saving…">Save photo</.button>
          <.button id="photo-another" type="button" phx-click="take-another">Take another</.button>
          <.button id="photo-cancel" navigate={@back}>Cancel</.button>
        </.form_actions>
      </div>
    </form>
    """
  end

  defp lead(nil), do: "It becomes the member's photo, and their ID card shows it."
  defp lead(member), do: "It becomes #{member.name}'s photo, and their ID card shows it."
end
