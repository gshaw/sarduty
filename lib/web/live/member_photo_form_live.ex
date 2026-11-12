defmodule Web.MemberPhotoFormLive do
  use Web,
      {:live_view_narrow_layout,
       access: :team, view_events: ["validate", "take-another"], member_events: ["save"]}

  alias App.Model.Member
  alias App.Model.MemberPhoto, as: WaitingPhoto
  alias App.Model.Team
  alias App.Operation.AddOwnPhoto
  alias App.Operation.SetMemberPhoto
  alias Service.MemberPhoto
  alias Web.PhotoCollectionLive

  # Add a photo, /teams/:subdomain/photos/members/new: someone takes or selects a photo,
  # places the face in the oval, and saves it. One task with a phone in hand, so a narrow
  # page.
  #
  # A team admin adds any member's (#1028), their own included, and it is the member's
  # photo at once. `?member=<id>` names the member; with none, a Member box lists the
  # current members. A member adds their own (#1029): no Member box, and whatever the URL
  # says the photo is of the person logged in. Theirs waits for a team admin
  # (AddOwnPhoto), and a decline of their last one shows above the examples.
  #
  # The photo uploads the moment it is picked. Service.MemberPhoto reads it, HEIC too,
  # into a JPEG the page shows for placing, since a browser cannot show every photo a
  # phone takes. That copy lives in this page's memory until it saves. The PhotoPlace
  # hook (assets/js/photo_place.js) moves it and fills in where it was placed.
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

    socket
    |> assign(page_title: "Add a photo", photo: nil, photo_count: 0)
    |> assign_who(params)
    |> allow_upload(:photo,
      accept: ~w(image/*),
      max_entries: 1,
      max_file_size: MemberPhoto.max_bytes(),
      auto_upload: true,
      progress: &handle_progress/3
    )
    |> then(&{:ok, &1})
  end

  # Who the photo is of. `own?` is a member adding their own, which waits; a team admin's
  # goes straight to the member's photo.
  defp assign_who(%{assigns: %{team_admin?: true, current_team: team}} = socket, params) do
    member = if id = params["member"], do: Member.find!(team, id)

    assign(socket,
      own?: false,
      member: member,
      members: if(member, do: nil, else: members(team)),
      declined: nil,
      back: back(team, member)
    )
  end

  defp assign_who(%{assigns: %{current_member: member, current_team: team}} = socket, _params) do
    assign(socket,
      own?: true,
      member: member,
      members: nil,
      declined: WaitingPhoto.declined_for_member(member),
      back: PhotoCollectionLive.view_path(team, :members)
    )
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
    %{member: member, photo: photo} = socket.assigns

    cond do
      is_nil(member) ->
        {:noreply, put_flash(socket, :error, "Select a member.")}

      is_nil(photo) ->
        {:noreply, put_flash(socket, :error, "Take a photo, or select one.")}

      true ->
        {:noreply, save(socket, member, photo, MemberPhoto.placement(params["photo"] || %{}))}
    end
  end

  # A member's own photo waits for a team admin.
  defp save(%{assigns: %{own?: true, current_team: team}} = socket, member, photo, placed) do
    {:ok, _waiting} = AddOwnPhoto.call(member, photo, placed)

    socket
    |> put_flash(:info, "Photo added. A team admin checks it.")
    |> push_navigate(to: PhotoCollectionLive.view_path(team, :members))
  end

  defp save(socket, member, photo, {turns, square}) do
    %{current_team: team, current_user: user} = socket.assigns

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

  # The Member box picks who the photo is of. With a member in the URL, or a member
  # adding their own, there is no box, and nothing the form sends changes who.
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
    <p id="photo-lead" class="lead">{lead(@own?, @member, @current_team)}</p>

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
        <.warning_text :if={@declined} id="photo-declined" class="mb-6">
          Your last photo was declined: {Web.MemberPhoto.reason(@declined)}.
          <span :if={@declined.decline_message} id="photo-declined-message" class="block">
            {@declined.decline_message}
          </span>
        </.warning_text>

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
        <p id="photo-place-hint" class="hint mb-2">
          Move or zoom it so {if @own?, do: "your", else: "the"} face fills the oval.
        </p>
        <%!-- A new photo is a new element, so it starts again from the middle square. --%>
        <Web.MemberPhoto.place
          id={"photo-place-#{@photo_count}"}
          src={@photo.src}
          width={@photo.width}
          height={@photo.height}
          labelledby="photo-place-label"
          describedby="photo-place-hint"
        />

        <.form_actions class="mt-6">
          <.button
            :if={@own?}
            id="photo-save"
            variant={:success}
            phx-disable-with="Adding…"
          >
            Add photo
          </.button>
          <.button :if={!@own?} id="photo-save" variant={:success} phx-disable-with="Saving…">
            Save photo
          </.button>
          <.button id="photo-another" type="button" phx-click="take-another">Take another</.button>
          <.button id="photo-cancel" navigate={@back}>Cancel</.button>
        </.form_actions>
      </div>
    </form>
    """
  end

  defp lead(true, _member, team),
    do: "#{team.name} puts it on your ID card. A team admin checks it first."

  defp lead(false, nil, _team), do: "It becomes the member's photo, and their ID card shows it."

  defp lead(false, member, _team),
    do: "It becomes #{member.name}'s photo, and their ID card shows it."
end
