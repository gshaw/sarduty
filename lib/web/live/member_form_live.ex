defmodule Web.MemberFormLive do
  use Web, :live_view_app_layout

  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Operation.SaveMember
  alias App.Operation.SetMemberLeft
  alias App.Operation.SetMemberPhoto
  alias App.ViewModel.MemberFormViewModel

  # Adding and changing members of a team on SAR Duty Records (docs/records.md). A D4H team
  # changes its members in D4H, so it has no such page.
  def mount(params, _session, socket) do
    team = socket.assigns.current_team
    unless D4H.records?(team), do: raise(Web.Status.NotFound)

    member = if id = params["id"], do: team |> Member.find!(id) |> Map.put(:team, team)
    today = DateTime.utc_now() |> Service.Convert.utc_to_local(team.timezone) |> elem(0)
    form = MemberFormViewModel.from_member(member, team.timezone, today)

    socket =
      socket
      |> assign(page_title: if(member, do: "Change #{member.name}", else: "Add member"))
      |> assign(member: member, form_data: form, photo_version: 0)
      |> assign_form(MemberFormViewModel.changeset(form))
      # cspell:ignore webp -- the WebP file extension
      # Records takes up to 10 MB and shrinks it. HEIC is refused there, but an iPhone's
      # browser sends a JPEG from a file input.
      |> allow_upload(:photo,
        accept: ~w(.jpg .jpeg .png .webp),
        max_entries: 1,
        max_file_size: 10_000_000
      )

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
      <:item label="Members" path={~p"/teams/#{@current_team}/members"} />
      <:item
        :if={@member}
        label={@member.name}
        path={~p"/teams/#{@current_team}/members/#{@member.id}"}
      />
      <:item label={if @member, do: "Change", else: "Add member"} />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>

    <.form for={@form} id="member-form" phx-change="validate" phx-submit="save" class="max-w-xl">
      <.error_summary form={@form} />
      <.input field={@form[:name]} label="Name" />
      <div class="grid grid-cols-2 gap-x-6">
        <.input field={@form[:ref_id]} label="ID (optional)" />
        <.input field={@form[:position]} label="Role (optional)" />
      </div>
      <.input field={@form[:email]} type="email" label="Email (optional)">
        Team admins log in with it, and tax credit letters go to it.
      </.input>
      <.input field={@form[:phone]} type="tel" label="Mobile phone (optional)" />
      <.input field={@form[:address]} type="textarea" rows="3" label="Address (optional)">
        For the mileage report and tax credit letters.
      </.input>
      <%!-- Side by side only where a date fits in half the width. --%>
      <div class="grid md:grid-cols-2 gap-x-6">
        <.input field={@form[:joined_on]} type="date" label="Joined" />
        <.input
          field={@form[:status]}
          type="select"
          label="Status"
          options={MemberFormViewModel.statuses()}
        />
      </div>
      <.input field={@form[:team_admin]} type="checkbox" label="Team admin">
        Team admins log in to SAR Duty and change the team's records.
      </.input>
      <.form_actions>
        <.button variant={:success}>{if @member, do: "Save member", else: "Add member"}</.button>
      </.form_actions>
    </.form>

    <section :if={@member} id="member-photo" class="mt-8 max-w-xl">
      <h2 class="heading">Photo</h2>
      <%!-- The version changes after a save, so the browser loads the new photo. --%>
      <p>
        <img
          id="member-photo-image"
          class="photo"
          src={~p"/teams/#{@current_team}/members/#{@member.id}/image?#{[v: @photo_version]}"}
          alt={"#{@member.name}'s photo"}
        />
      </p>
      <form id="photo-form" phx-change="validate-photo" phx-submit="save-photo">
        <.label for={@uploads.photo.ref}>New photo</.label>
        <.hint>
          A JPEG, PNG, or WebP of the member's face, under 10 MB. Their ID card shows it.
        </.hint>
        <.live_file_input upload={@uploads.photo} class="my-2" />
        <.error :for={error <- upload_errors(@uploads.photo)}>{upload_error(error)}</.error>
        <%= for entry <- @uploads.photo.entries do %>
          <.error :for={error <- upload_errors(@uploads.photo, entry)}>{upload_error(error)}</.error>
        <% end %>
        <.form_actions>
          <.button id="save-photo" variant={:success}>Save photo</.button>
          <:trailing>
            <.button
              id="remove-photo"
              type="button"
              phx-click="remove-photo"
              data-confirm={"Remove #{@member.name}'s photo? Their ID card shows a placeholder until you add one."}
            >
              Remove photo
            </.button>
          </:trailing>
        </.form_actions>
      </form>
    </section>

    <section :if={@member} id="member-left" class="mt-8 max-w-xl">
      <h2 class="heading">Leaving the team</h2>
      <%= if @member.d4h_status == "RETIRED" do %>
        <p>
          {@member.name} left on {Service.Format.date_long(@member.left_at, @current_team.timezone)}.
        </p>
        <.button id="member-rejoin" type="button" phx-click="rejoin">Mark as rejoined</.button>
      <% else %>
        <p>
          A member who leaves keeps their attendance and letters. They no longer count as a team
          admin or a current member.
        </p>
        <.button
          id="member-leave"
          type="button"
          variant={:danger}
          phx-click="leave"
          data-confirm={"Mark #{@member.name} as left today?"}
        >
          Mark as left
        </.button>
      <% end %>
    </section>
    """
  end

  def handle_event("validate", %{"form" => params}, socket) do
    changeset =
      socket.assigns.form_data
      |> MemberFormViewModel.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"form" => params}, socket) do
    %{current_team: team, current_user: user, member: member} = socket.assigns

    case SaveMember.call(team, member, params, user, DateTime.utc_now()) do
      {:ok, saved} -> {:noreply, saved(socket, saved, "Saved #{params["name"]}.")}
      {:error, %Ecto.Changeset{} = changeset} -> {:noreply, assign_form(socket, changeset)}
      {:error, text} -> {:noreply, put_flash(socket, :error, text)}
    end
  end

  def handle_event(event, _params, socket) when event in ["leave", "rejoin"] do
    %{current_team: team, current_user: user, member: member} = socket.assigns

    case SetMemberLeft.call(team, member, event == "leave", user, DateTime.utc_now()) do
      {:ok, saved} ->
        text = if event == "leave", do: "Marked as left.", else: "Marked as rejoined."
        {:noreply, saved(socket, saved, "#{member.name}: #{text}")}

      {:error, text} ->
        {:noreply, put_flash(socket, :error, text)}
    end
  end

  def handle_event("validate-photo", _params, socket), do: {:noreply, socket}

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

  defp set_photo(socket, bytes, text) do
    %{current_team: team, current_user: user, member: member} = socket.assigns

    case SetMemberPhoto.call(team, member, bytes, user, DateTime.utc_now()) do
      :ok -> socket |> put_flash(:info, text) |> update(:photo_version, &(&1 + 1))
      {:error, text} -> put_flash(socket, :error, text)
    end
  end

  defp upload_error(:too_large), do: "That file is too large. Use one under 10 MB."
  defp upload_error(:not_accepted), do: "Use a JPEG, PNG, or WebP."
  defp upload_error(:too_many_files), do: "Select one file."
  defp upload_error(_error), do: "That file did not upload. Try again."

  # The member page, or the list when the copy hasn't caught up yet.
  defp saved(socket, member, text) do
    team = socket.assigns.current_team

    path =
      if member, do: ~p"/teams/#{team}/members/#{member.id}", else: ~p"/teams/#{team}/members"

    socket |> put_flash(:info, text) |> push_navigate(to: path)
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "form"))
end
