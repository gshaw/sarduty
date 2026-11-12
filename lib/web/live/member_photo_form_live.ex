defmodule Web.MemberPhotoFormLive do
  use Web,
      {:live_view_narrow_layout,
       access: :team,
       view_events: ["validate", "take-another", "clean-up"],
       member_events: ["save"]}

  alias App.Model.Member
  alias App.Model.MemberPhoto
  alias App.Model.PhotoAsk
  alias App.Model.Team
  alias App.Operation.AddOwnPhoto
  alias App.Operation.CleanUpPhoto
  alias App.Operation.SetMemberPhoto
  alias Web.Navigation
  alias Web.PhotoAskLinks
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
  # The email that asks a member for a photo (#1030) opens the same page at
  # /photos/:token, with no login: the token names the ask, and so the member. Nothing
  # the session or the form says changes who. Their photo waits too, and adding it
  # closes the ask, so the link works once. One too old, or whose ask closed, says so.
  #
  # The photo uploads the moment it is picked. Service.MemberPhoto reads it, HEIC too,
  # into a JPEG the page shows for placing, since a browser cannot show every photo a
  # phone takes. That copy lives in this page's memory until it saves. The PhotoPlace
  # hook (assets/js/photo_place.js) moves it and fills in where it was placed.
  #
  # While Clean up is available (#1031, App.Operation.CleanUpPhoto) it runs by itself on
  # the photo picked, and the page says so while it waits. The cleaned-up photo arrives
  # placed in the square, under a Clean up switch that is on; off shows the photo as
  # taken. The page keeps both, and saves the one the switch shows. SAR Duty warns about
  # what it can tell for sure, and never blocks: with a warning, Take another leads.
  # When Clean up does not answer, a toast says so and the photo is placed as taken.
  # With Clean up off, nothing here mentions it.
  @rules [
    "Head and shoulders, facing the camera",
    "A plain, light wall behind you",
    "Daylight or a bright room",
    "No hat or sunglasses. Glasses are fine."
  ]

  # The rules while Clean up is available: the wall no longer matters.
  @clean_up_rules [
    "Head and shoulders, facing the camera",
    "Daylight or a bright room",
    "No hat or sunglasses. Glasses are fine.",
    "Any background. SAR Duty removes it."
  ]

  # The drawn examples in priv/static/images, so the guide shows nobody real. Busy
  # background goes while Clean up is available.
  @busy_background {"photo-guide-busy-background.svg", "Busy background"}
  @bad [
    {"photo-guide-sunglasses.svg", "Sunglasses"},
    {"photo-guide-hat.svg", "Hat or helmet"},
    {"photo-guide-dark.svg", "Too dark"},
    {"photo-guide-someone-else.svg", "Someone else in it"},
    @busy_background
  ]

  # The ask's link. A token that was never one is not found.
  def mount(%{"token" => token}, _session, socket) do
    case PhotoAskLinks.find_ask(token) do
      {:ok, ask} ->
        {:ok, socket |> assign(token: token) |> assign_asked(ask) |> assign_page()}

      :ended ->
        {:ok, assign(socket, page_title: "This link no longer works", ended?: true)}

      :error ->
        raise Web.Status.NotFound
    end
  end

  def mount(params, _session, socket) do
    team = socket.assigns.current_team
    if !Team.photos?(team), do: raise(Web.Status.NotFound)

    {:ok, socket |> assign(team: team, token: nil) |> assign_who(params) |> assign_page()}
  end

  defp assign_page(socket) do
    socket
    |> assign(page_title: "Add a photo", photo: nil, photo_count: 0, ended?: false, done?: false)
    |> assign(clean_up_available?: CleanUpPhoto.available?())
    |> assign_no_clean_up()
    |> allow_upload(:photo,
      accept: ~w(image/*),
      max_entries: 1,
      max_file_size: Service.MemberPhoto.max_bytes(),
      auto_upload: true,
      progress: &handle_progress/3
    )
  end

  # Nothing cleaned up: before a photo is picked, with Clean up off, or when it did not
  # answer. `cleaned` is the cleaned-up photo, `clean_up?` the switch, and `warnings`
  # what CleanUpPhoto found.
  defp assign_no_clean_up(socket),
    do: assign(socket, cleaning?: false, cleaned: nil, clean_up?: false, warnings: [])

  # The member the ask names, adding their own. Logged in to the ask's team, the bar
  # names it, as the reply links do.
  defp assign_asked(socket, %PhotoAsk{team: team, member: member}) do
    socket =
      if Navigation.opens_team?(socket.assigns, team),
        do: assign(socket, current_team: team),
        else: socket

    assign(socket,
      team: team,
      own?: true,
      member: member,
      members: nil,
      declined: MemberPhoto.declined_for_member(member),
      back: nil
    )
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
      declined: MemberPhoto.declined_for_member(member),
      back: PhotoCollectionLive.view_path(team, :yours)
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

    case Service.MemberPhoto.prepare(bytes) do
      {:ok, photo} ->
        middle = Service.MemberPhoto.face_placement({photo.width, photo.height}, nil)

        {:noreply,
         socket
         |> assign(photo: showable(photo, middle))
         |> update(:photo_count, &(&1 + 1))
         |> clean_up(photo)}

      {:error, text} ->
        {:noreply, put_flash(socket, :error, text)}
    end
  end

  defp handle_progress(:photo, _entry, socket), do: {:noreply, socket}

  # A photo the page can show and place: its bytes as the `src`, and where it starts.
  defp showable(photo, placed) do
    Map.merge(photo, %{
      src: "data:image/jpeg;base64," <> Base.encode64(photo.bytes),
      placed: placed
    })
  end

  # Clean up runs by itself, apart from the page, which says so while it waits.
  defp clean_up(%{assigns: %{clean_up_available?: true}} = socket, photo) do
    socket
    |> assign(cleaning?: true)
    |> start_async(:clean_up, fn -> CleanUpPhoto.call(photo, :member) end)
  end

  defp clean_up(socket, _photo), do: socket

  # The cleaned-up photo arrives placed, with the switch on.
  def handle_async(:clean_up, {:ok, {:ok, result}}, %{assigns: %{cleaning?: true}} = socket) do
    {:noreply,
     assign(socket,
       cleaning?: false,
       cleaned: showable(result.cleaned, result.placed),
       clean_up?: true,
       warnings: result.warnings
     )}
  end

  # It did not answer: the photo is placed as taken, as with Clean up off.
  def handle_async(:clean_up, _no_answer, %{assigns: %{cleaning?: true}} = socket) do
    place =
      if socket.assigns.own?, do: "Place your photo yourself.", else: "Place the photo yourself."

    {:noreply,
     socket |> assign_no_clean_up() |> put_flash(:error, "Clean up did not answer. #{place}")}
  end

  # An answer for a photo the person has left.
  def handle_async(:clean_up, _late, socket), do: {:noreply, socket}

  def handle_event("validate", params, socket),
    do: {:noreply, socket |> pick_member(params) |> refuse_upload()}

  def handle_event("take-another", _params, socket) do
    {:noreply, socket |> cancel_async(:clean_up) |> assign(photo: nil) |> assign_no_clean_up()}
  end

  # The Clean up switch: which of the two photos the square shows.
  def handle_event("clean-up", _params, socket),
    do: {:noreply, update(socket, :clean_up?, &(!&1 and socket.assigns.cleaned != nil))}

  def handle_event("save", params, socket) do
    socket = pick_member(socket, params)
    %{member: member, photo: photo} = socket.assigns

    cond do
      is_nil(member) ->
        {:noreply, put_flash(socket, :error, "Select a member.")}

      is_nil(photo) ->
        {:noreply, put_flash(socket, :error, "Take a photo, or select one.")}

      true ->
        placed = Service.MemberPhoto.placement(params["photo"] || %{})
        {:noreply, save(socket, member, photo, placed)}
    end
  end

  # From the ask's link: the ask is read again, since it may have closed while the page
  # was open. The photo waits, and the page says so, with nowhere to go without a login.
  defp save(%{assigns: %{token: token}} = socket, _member, photo, placed) when is_binary(token) do
    case PhotoAskLinks.find_ask(token) do
      {:ok, ask} ->
        {:ok, _waiting} = AddOwnPhoto.call(ask.member, photo, placed, kept_clean_up(socket))

        socket
        |> assign(page_title: "Photo added", done?: true, photo: nil)
        |> assign_no_clean_up()

      _ended ->
        socket
        |> assign(page_title: "This link no longer works", ended?: true, photo: nil)
        |> assign_no_clean_up()
    end
  end

  # A member's own photo waits for a team admin.
  defp save(%{assigns: %{own?: true, team: team}} = socket, member, photo, placed) do
    {:ok, _waiting} = AddOwnPhoto.call(member, photo, placed, kept_clean_up(socket))

    socket
    |> put_flash(:info, "Photo added. A team admin checks it.")
    |> push_navigate(to: PhotoCollectionLive.view_path(team, :yours))
  end

  # A team admin's goes as the switch shows it: nothing waits, so nothing else is kept.
  defp save(socket, member, _photo, {turns, square}) do
    %{team: team, current_user: user} = socket.assigns

    with {:ok, jpeg} <- Service.MemberPhoto.place(shown(socket.assigns).bytes, turns, square),
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

  # The photo in the square: the cleaned-up one with the Clean up switch on, or the photo
  # as taken.
  defp shown(%{cleaned: %{} = cleaned, clean_up?: true}), do: cleaned
  defp shown(%{photo: photo}), do: photo

  # What a waiting photo keeps of Clean up, as AddOwnPhoto takes it: the cleaned-up
  # photo and where the switch is. Nil with Clean up off, or when it did not answer.
  defp kept_clean_up(%{assigns: %{cleaned: nil}}), do: nil
  defp kept_clean_up(%{assigns: %{cleaned: cleaned, clean_up?: on?}}), do: {cleaned, on?}

  # The Member box picks who the photo is of. With a member in the URL, or a member
  # adding their own, there is no box, and nothing the form sends changes who.
  defp pick_member(%{assigns: %{members: nil}} = socket, _params), do: socket

  defp pick_member(socket, %{"member_id" => id}) do
    known? = Enum.any?(socket.assigns.members, fn {_name, value} -> value == id end)
    assign(socket, member: if(known?, do: Member.find!(socket.assigns.team, id)))
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

  def render(%{ended?: true} = assigns) do
    ~H"""
    <h1 class="title">This link no longer works</h1>
    <p id="photo-link-ended">Ask a team admin for a new one.</p>
    """
  end

  def render(%{done?: true} = assigns) do
    ~H"""
    <h1 class="title">Photo added</h1>
    <p id="photo-link-done">A team admin checks it before your ID card shows it.</p>
    """
  end

  def render(assigns) do
    assigns =
      if assigns.clean_up_available?,
        do: assign(assigns, rules: @clean_up_rules, bad: List.delete(@bad, @busy_background)),
        else: assign(assigns, rules: @rules, bad: @bad)

    assigns = assign(assigns, shown: assigns.photo && shown(assigns))

    ~H"""
    <.breadcrumbs :if={!@token}>
      <:item label="Photos" path={PhotoCollectionLive.path(@team)} />
      <:item label="Add a photo" />
    </.breadcrumbs>
    <p :if={@token} id="photo-team" class="hint mb-1">{@team.name}</p>
    <h1 class="title">Add a photo</h1>
    <p id="photo-lead" class="lead">{lead(@own?, @member, @team)}</p>

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
          <.button :if={@back} id="photo-cancel" navigate={@back}>Cancel</.button>
        </.form_actions>
        <p :if={@clean_up_available?} id="photo-clean-up-line" class="hint mt-2">
          {clean_up_line(@own?)}
        </p>
        <.spinner :if={@uploads.photo.entries != []} id="photo-reading" class="block mt-4">
          Reading the photo…
        </.spinner>
        <%!-- Both buttons open this one input: Take a photo with the camera asked for
          (capture="user"), Select a photo without. --%>
        <.live_file_input upload={@uploads.photo} class="hidden" />
      </div>

      <.spinner :if={@photo && @cleaning?} id="photo-cleaning" class="block">
        Cleaning up…
      </.spinner>

      <div :if={@photo && !@cleaning?} id="photo-placed">
        <.warning_text
          :for={warning <- @warnings}
          id={"photo-warning-#{warning_key(warning)}"}
          class="mb-4"
        >
          {warning_text(warning, @own?)}
        </.warning_text>
        <span id="photo-place-label" class="label block">Photo</span>
        <p id="photo-place-hint" class="hint mb-2">{place_hint(@clean_up?, @own?)}</p>
        <%!-- A new photo is a new element, and so is the other side of the Clean up
          switch, so each starts again from where it is placed. --%>
        <Web.MemberPhoto.place
          id={"photo-place-#{@photo_count}-#{if @clean_up?, do: "cleaned", else: "taken"}"}
          src={@shown.src}
          width={@shown.width}
          height={@shown.height}
          placed={@shown.placed}
          label_id="photo-place-label"
          hint_id="photo-place-hint"
        />
        <.switch
          :if={@cleaned}
          id="photo-clean-up"
          label="Clean up"
          checked={@clean_up?}
          phx-click="clean-up"
          class="mt-4"
        >
          {clean_up_hint(@own?)}
        </.switch>

        <%!-- SAR Duty warns and never blocks: with a warning, Take another leads. --%>
        <.form_actions class="mt-6">
          <.button
            :if={@warnings != []}
            id="photo-another"
            type="button"
            variant={:success}
            phx-click="take-another"
          >
            Take another
          </.button>
          <.button
            id="photo-save"
            variant={if @warnings == [], do: :success, else: :default}
            phx-disable-with={if @own?, do: "Adding…", else: "Saving…"}
          >
            {if @own?, do: "Add photo", else: "Save photo"}
          </.button>
          <.button
            :if={@warnings == []}
            id="photo-another"
            type="button"
            phx-click="take-another"
          >
            Take another
          </.button>
          <.button :if={@back} id="photo-cancel" navigate={@back}>Cancel</.button>
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

  # Clean up's words, for a member adding their own (`own?`) and for a team admin adding
  # a member's.
  defp clean_up_line(true),
    do:
      "SAR Duty cleans it up: it removes the background and centres your face. You see the result before anyone else does."

  defp clean_up_line(false),
    do:
      "SAR Duty cleans it up: it removes the background and centres the face. You see the result before you save it."

  defp place_hint(true, true), do: "Cleaned up. Move or zoom it if your face is not in the oval."
  defp place_hint(true, false), do: "Cleaned up. Move or zoom it if the face is not in the oval."
  defp place_hint(false, true), do: "Move or zoom it so your face fills the oval."
  defp place_hint(false, false), do: "Move or zoom it so the face fills the oval."

  defp clean_up_hint(true),
    do: "Removes the background and centres your face. Turn it off to use your photo as it is."

  defp clean_up_hint(false),
    do: "Removes the background and centres the face. Turn it off to use the photo as it is."

  defp warning_key({:faces, _count}), do: "faces"
  defp warning_key(:no_face), do: "no-face"
  defp warning_key(:dark), do: "dark"

  defp warning_text({:faces, count}, own?) do
    faces = Service.Format.count(count, one: "%d face", many: "%d faces")
    "#{faces} in this photo. Take one with only #{if own?, do: "you", else: "the member"} in it."
  end

  defp warning_text(:no_face, _own?),
    do: "No face found in this photo. Take another, or place it yourself."

  defp warning_text(:dark, _own?),
    do: "This photo is dark. Take another in daylight or a bright room."
end
