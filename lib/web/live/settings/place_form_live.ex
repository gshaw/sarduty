defmodule Web.Settings.PlaceFormLive do
  use Web, :live_view_app_layout

  alias App.Adapter.D4H
  alias App.Model.LocationBookmark
  alias App.Operation.SaveLocationBookmark
  alias App.ViewModel.LocationBookmarkFormViewModel

  # Adding, changing, and deleting a saved place on a SAR Duty Records team (#614). A D4H
  # team changes its bookmarks in D4H, so the page is not found there.
  def mount(params, _session, socket) do
    team = socket.assigns.current_team
    if !D4H.records?(team), do: raise(Web.Status.NotFound)

    place = if id = params["id"], do: LocationBookmark.find!(team, id)

    socket =
      socket
      |> assign(place: place, page_title: if(place, do: "Change place", else: "Add place"))
      |> assign_form(
        place
        |> LocationBookmarkFormViewModel.from_bookmark()
        |> LocationBookmarkFormViewModel.changeset()
      )

    {:ok, socket}
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "place"))

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Places" path={~p"/teams/#{@current_team}/settings/places"} />
      <:item label={if @place, do: LocationBookmark.name(@place), else: @page_title} />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>

    <.form for={@form} id="place-form" class="measure" phx-change="validate" phx-submit="save">
      <.error_summary form={@form} />
      <.input field={@form[:title]} label="Name">
        Such as "Hall". Short names are easiest to find.
      </.input>
      <.input field={@form[:place]} label="Address (optional)">
        As it goes on an activity, like 17543 20 Ave, Surrey.
      </.input>
      <.input field={@form[:pin]} label="Latitude and longitude (optional)">
        Paste them from a map, like 49.10788, -122.82894.
      </.input>

      <.form_actions>
        <.button id="place-save" variant={:success} phx-disable-with="Saving…">
          {if @place, do: "Save place", else: "Add place"}
        </.button>
        <.button navigate={~p"/teams/#{@current_team}/settings/places"}>Cancel</.button>
        <:trailing :if={@place}>
          <.button
            id="place-delete"
            type="button"
            variant={:danger}
            phx-click="delete"
            phx-disable-with="Deleting…"
            data-confirm={"Delete #{LocationBookmark.name(@place)}? Activities keep their address and pin."}
          >
            Delete place
          </.button>
        </:trailing>
      </.form_actions>
    </.form>
    """
  end

  def handle_event("validate", %{"place" => params}, socket) do
    changeset =
      socket.assigns.place
      |> LocationBookmarkFormViewModel.from_bookmark()
      |> LocationBookmarkFormViewModel.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"place" => params}, socket) do
    %{current_team: team, current_user: user, place: place} = socket.assigns

    case SaveLocationBookmark.save(team, place, params, user, DateTime.utc_now()) do
      {:ok, title} -> {:noreply, done(socket, "Saved #{title}.")}
      {:error, %Ecto.Changeset{} = changeset} -> {:noreply, assign_form(socket, changeset)}
      {:error, text} -> {:noreply, put_flash(socket, :error, text)}
    end
  end

  def handle_event("delete", _params, socket) do
    %{current_team: team, current_user: user, place: place} = socket.assigns

    case SaveLocationBookmark.delete(team, place, user, DateTime.utc_now()) do
      :ok -> {:noreply, done(socket, "Deleted #{LocationBookmark.name(place)}.")}
      {:error, text} -> {:noreply, put_flash(socket, :error, text)}
    end
  end

  defp done(socket, text) do
    socket
    |> put_flash(:info, text)
    |> push_navigate(to: ~p"/teams/#{socket.assigns.current_team}/settings/places")
  end
end
