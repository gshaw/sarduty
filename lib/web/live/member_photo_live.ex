defmodule Web.MemberPhotoLive do
  use Web, :live_view_app_layout

  import Web.Components.FileDrop

  alias App.Model.Member
  alias App.Operation.CheckMemberPhoto
  alias App.Operation.SetMemberPhoto

  # Change photo, from the member's Actions, on every team (#1028): the photo, the
  # original to download, a new one to save, and Remove photo. The photo goes to the
  # team's records, D4H or Records (SetMemberPhoto); SAR Duty keeps no copy.
  #
  # Whether there's a photo is asked as the page opens: the nightly check runs only on
  # teams with ID cards on, and a photo set in D4H's web app lands there first.
  def mount(%{"id" => id}, _session, socket) do
    team = socket.assigns.current_team
    member = team |> Member.find!(id) |> Map.put(:team, team) |> CheckMemberPhoto.call()

    socket =
      socket
      |> assign(page_title: "Change #{member.name}'s photo", member: member)
      # cspell:ignore webp -- the WebP file extension
      # SetMemberPhoto shrinks it before it goes. An iPhone's browser sends a JPEG from a
      # file input, not HEIC.
      |> allow_upload(:photo,
        accept: ~w(.jpg .jpeg .png .webp),
        max_entries: 1,
        max_file_size: 10_000_000
      )

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Members" path={~p"/teams/#{@current_team}/members"} />
      <:item label={@member.name} path={member_path(@current_team, @member)} />
      <:item label="Change photo" />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>

    <section id="member-photo" class="measure">
      <%= if @member.has_photo do %>
        <p>
          <img
            id="member-photo-image"
            class="photo"
            src={
              ~p"/teams/#{@current_team}/members/#{@member.id}/image?#{[v: Member.photo_version(@member)]}"
            }
            alt={"#{@member.name}'s photo"}
            data-hide-on-error
          />
        </p>
        <p>
          <.button
            id="download-photo"
            href={~p"/teams/#{@current_team}/members/#{@member.id}/image/original"}
          >
            Download original photo
          </.button>
        </p>
      <% else %>
        <p id="member-photo-none">{@member.name} has no photo.</p>
      <% end %>

      <form id="photo-form" class="mt-6" phx-change="validate-photo" phx-submit="save-photo">
        <.file_drop
          id="member-photo-file"
          upload={@uploads.photo}
          label="New photo"
          kinds="a JPEG, PNG, or WebP"
        >
          A JPEG, PNG, or WebP of the member's face, under 10 MB. Their ID card shows it.
        </.file_drop>
        <.form_actions>
          <.button id="save-photo" variant={:success} phx-disable-with="Saving…">Save photo</.button>
          <.button id="photo-cancel" navigate={member_path(@current_team, @member)}>Cancel</.button>
          <:trailing :if={@member.has_photo}>
            <.button
              id="remove-photo"
              type="button"
              variant={:danger}
              phx-click="remove-photo"
              phx-disable-with="Removing…"
              data-confirm={"Remove #{@member.name}'s photo? Their ID card shows a placeholder until you add one."}
            >
              Remove photo
            </.button>
          </:trailing>
        </.form_actions>
      </form>
    </section>
    """
  end

  def handle_event("validate-photo", _params, socket), do: {:noreply, socket}

  def handle_event("cancel-upload", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :photo, ref)}

  def handle_event("save-photo", _params, socket) do
    case consume_uploaded_entries(socket, :photo, fn %{path: path}, _entry ->
           {:ok, File.read!(path)}
         end) do
      [bytes] -> {:noreply, set_photo(socket, bytes, "Photo saved.")}
      [] -> {:noreply, put_flash(socket, :error, "Select a photo.")}
    end
  end

  def handle_event("remove-photo", _params, socket),
    do: {:noreply, set_photo(socket, nil, "Photo removed.")}

  # Back to the member's page, whose header shows the new photo. A refusal stays here.
  defp set_photo(socket, bytes, text) do
    %{current_team: team, current_user: user, member: member} = socket.assigns

    case SetMemberPhoto.call(team, member, bytes, user, DateTime.utc_now()) do
      :ok ->
        socket
        |> put_flash(:info, "#{member.name}: #{text}")
        |> push_navigate(to: member_path(team, member))

      {:error, text} ->
        put_flash(socket, :error, text)
    end
  end

  defp member_path(team, member), do: ~p"/teams/#{team}/members/#{member.id}"
end
