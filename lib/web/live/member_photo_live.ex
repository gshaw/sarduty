defmodule Web.MemberPhotoLive do
  use Web, :live_view_app_layout

  alias App.Model.Member
  alias App.Model.MemberPhoto
  alias App.Model.Team
  alias App.Operation.AcceptMemberPhoto
  alias App.Operation.DeclineMemberPhoto
  alias Service.Format
  alias Web.PhotoCollectionLive

  # Check a photo (#1029), /teams/:subdomain/photos/members/:id: a photo a member added
  # of themselves, on the certificate review layout. The square starts where the member
  # placed it, with Add a photo's tools, so a team admin fixes the framing rather than
  # declining for it. Beside it: the photo as taken and the one on the ID card now, then
  # Accept, which sends the square as it is placed now (AcceptMemberPhoto), and Decline,
  # with one reason and a message the member sees (DeclineMemberPhoto). Once decided, the
  # page says who decided and why, and the photo is gone.
  def mount(%{"id" => id}, _session, socket) do
    team = socket.assigns.current_team
    if !Team.photos?(team), do: raise(Web.Status.NotFound)
    photo = MemberPhoto.find!(team, id)

    socket
    |> assign(photo: photo, page_title: "Photo from #{photo.member.name}")
    |> assign_decline_form(Ecto.Changeset.change(photo))
    |> then(&{:ok, &1})
  end

  defp assign_decline_form(socket, changeset),
    do: assign(socket, :decline_form, to_form(changeset, as: "decline"))

  def handle_event("accept", params, socket) do
    %{current_team: team, current_user: user, photo: photo} = socket.assigns
    placed = Service.MemberPhoto.placement(params["photo"] || %{})

    case AcceptMemberPhoto.call(team, photo, placed, user, DateTime.utc_now()) do
      {:ok, _accepted} ->
        {:noreply, done(socket, :info, "Photo accepted.")}

      {:error, :decided} ->
        {:noreply, decided(socket)}

      # The team's records refused it: the photo stays waiting, where it was placed.
      {:error, text} when is_binary(text) ->
        {:noreply, put_flash(socket, :error, text)}

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, "SAR Duty cannot read this photo. Decline it instead.")}
    end
  end

  def handle_event("decline", %{"decline" => values}, socket) do
    %{current_team: team, current_user: user, photo: photo} = socket.assigns
    %{"decline_message" => message} = values
    reason = values["decline_reason"]

    case DeclineMemberPhoto.call(team, photo, reason, message, user, DateTime.utc_now()) do
      {:ok, _declined} -> {:noreply, done(socket, :info, "Photo declined.")}
      {:error, :decided} -> {:noreply, decided(socket)}
      {:error, changeset} -> {:noreply, assign_decline_form(socket, changeset)}
    end
  end

  # Back to the photos that wait, for the next one.
  defp done(socket, kind, text) do
    socket
    |> put_flash(kind, text)
    |> push_navigate(to: PhotoCollectionLive.view_path(socket.assigns.current_team, :waiting))
  end

  # Decided since the page opened, or the member added another, which replaced it.
  defp decided(socket) do
    done(
      socket,
      :error,
      "This photo is no longer waiting. Another team admin decided it, or the member added another."
    )
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Photos" path={PhotoCollectionLive.view_path(@current_team, :members)} />
      <:item label={@page_title} />
    </.breadcrumbs>
    <h1 class="title">Photo from {@photo.member.name}</h1>

    <div class="cert-layout photo-check">
      <div class="cert-layout-file">
        <%!-- Accept, in the panel, sends this form: the square as it is placed now. --%>
        <form :if={@photo.status == :waiting} id="accept-form" phx-submit="accept">
          <span id="photo-place-label" class="sr-only">Photo</span>
          <p id="photo-place-hint" class="hint mb-2">Move or zoom it so the face fills the oval.</p>
          <Web.MemberPhoto.place
            id={"photo-place-#{@photo.id}"}
            src={Web.MemberPhoto.waiting_path(@current_team, @photo, :taken)}
            width={@photo.width}
            height={@photo.height}
            placed={MemberPhoto.placed(@photo)}
            label_id="photo-place-label"
            hint_id="photo-place-hint"
          />
        </form>
        <p :if={@photo.status != :waiting} id="photo-file-gone" class="hint">
          SAR Duty deleted its copy of the photo when it was {if @photo.status == :accepted,
            do: "accepted",
            else: "declined"}.
        </p>
      </div>
      <aside class="cert-layout-panel">
        <dl id="photo-details" class="mb-8">
          <dt>Member</dt>
          <dd>
            <.a navigate={~p"/teams/#{@current_team}/members/#{@photo.member_id}"}>{@photo.member.name}</.a>
          </dd>
          <dt>Added</dt>
          <dd>{Format.datetime_short(@photo.inserted_at, @current_team.timezone)}</dd>
          <div :if={@photo.status == :waiting}>
            <dt>Compare</dt>
            <dd>
              <div id="photo-compare" class="photo-compare">
                <figure>
                  <img
                    id="photo-as-taken"
                    src={Web.MemberPhoto.waiting_path(@current_team, @photo, :taken)}
                    alt=""
                  />
                  <figcaption>As taken</figcaption>
                </figure>
                <figure :if={@photo.member.has_photo}>
                  <img
                    id="photo-on-card"
                    src={Web.MemberPhoto.path(@current_team, @photo.member)}
                    alt=""
                  />
                  <figcaption>On the card now</figcaption>
                </figure>
              </div>
            </dd>
          </div>
          <div :if={@photo.status != :waiting}>
            <dt>Status</dt>
            <dd id="photo-status">
              <.badge :if={@photo.status == :declined} kind={:warning}>Declined</.badge>
              <span :if={@photo.status == :accepted}>Accepted</span>
              <span class="hint">
                {Format.datetime_short(@photo.decided_at, @current_team.timezone)}{if @photo.decided_by_user,
                  do: ", #{@photo.decided_by_user.email}"}
              </span>
            </dd>
          </div>
          <div :if={@photo.status == :declined}>
            <dt>Why not</dt>
            <dd id="photo-decline-reason">
              {Web.MemberPhoto.reason(@photo)}
              <span :if={@photo.decline_message} class="hint block">{@photo.decline_message}</span>
            </dd>
          </div>
        </dl>

        <section :if={@photo.status == :waiting} id="photo-accept">
          <h2 class="subheading">Accept</h2>
          <p class="hint">
            It becomes {Member.first_name(@photo.member)}'s photo. Phones that hold their ID card get it within a minute.
          </p>
          <.form_actions>
            <.button
              id="photo-accept-button"
              form="accept-form"
              variant={:success}
              phx-disable-with="Accepting…"
            >
              Accept photo
            </.button>
          </.form_actions>
        </section>

        <section :if={@photo.status == :waiting} id="photo-decline" class="mt-8">
          <h2 class="subheading">Decline</h2>
          <.form for={@decline_form} id="decline-form" phx-submit="decline">
            <.input
              field={@decline_form[:decline_reason]}
              type="radios"
              label="Why not"
              options={for {key, text} <- MemberPhoto.reasons(), do: {text, key}}
            >
              {Member.first_name(@photo.member)} sees this beside the examples, and adds another.
            </.input>
            <.input
              field={@decline_form[:decline_message]}
              type="textarea"
              rows="2"
              maxlength="300"
              label="A message (optional)"
            />
            <.form_actions>
              <.button id="photo-decline-button" variant={:danger}>Decline photo</.button>
            </.form_actions>
          </.form>
        </section>
      </aside>
    </div>
    """
  end
end
