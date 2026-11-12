defmodule Web.ActivityPhotosLive do
  @moduledoc """
  An activity's Photos tab (#1032), on an exercise or an event while the team has
  activity photos (App.Operation.AddActivityPhotos.available?/1). Web.ActivityLive draws
  the page around it, as it does the Members tab; this module owns the tab: the photos
  the viewer sees, and for a team admin the waiting ones checked.

  Everyone on the team sees the accepted photos, newest first, each with who added it
  and when, and Add photos when they may add. A member also sees their own waiting ones,
  marked Waiting, and never another member's (App.Model.ActivityPhoto.visible/2).

  A team admin gets a Waiting section over them: every waiting photo as a checked tile,
  with Accept and Delete for the checked ones. They start checked, as review lists do,
  and a cleared tile stays cleared. Members send none of its events: the team pages'
  hook drops them, and a team admin viewing as a member is told nothing is saved.
  """
  use Web, {:live_view_app_layout, access: :team}

  alias App.Model.ActivityPhoto
  alias App.Operation.AcceptActivityPhotos
  alias App.Operation.AddActivityPhotos
  alias App.Operation.DeleteActivityPhotos
  alias Service.Format
  alias Web.ActivityLive

  def mount(params, session, socket), do: ActivityLive.mount(params, session, socket)

  def handle_params(params, uri, socket) do
    {:noreply, socket} = ActivityLive.handle_params(params, uri, socket)
    {:noreply, load(socket)}
  end

  # The photos the viewer sees, with every waiting one checked, and the tab's count.
  defp load(socket) do
    %{current_team: team, activity: activity, team_admin?: team_admin?, now: now} = socket.assigns
    viewer = %{team_admin?: team_admin?, member: socket.assigns.current_member}
    photos = ActivityPhoto.for_activity(activity, viewer)

    waiting =
      if team_admin?, do: for(%{status: :waiting} = photo <- photos, do: photo.id), else: []

    assign(socket,
      photos: photos,
      photo_ticks: MapSet.new(waiting),
      photos_waiting: length(waiting),
      may_add_photos?: AddActivityPhotos.may_add?(team, activity, viewer, now)
    )
  end

  # The tiles checked, kept so a re-render never checks one again.
  def handle_event("tick-photos", params, socket),
    do: {:noreply, assign(socket, photo_ticks: ticks(socket, params))}

  def handle_event("accept-photos", params, socket) do
    %{current_team: team, activity: activity, current_user: user} = socket.assigns

    case socket |> ticks(params) |> MapSet.to_list() do
      [] ->
        {:noreply, put_flash(socket, :error, "Check the photos to accept first.")}

      ids ->
        {:ok, count} = AcceptActivityPhotos.call(team, activity, ids, user, DateTime.utc_now())

        text = Format.count(count, one: "%d photo accepted.", many: "%d photos accepted.")
        {:noreply, socket |> load() |> put_flash(:info, text)}
    end
  end

  # Delete takes the tiles the page has checked: the button is outside what a form sends.
  def handle_event("delete-photos", _params, socket) do
    %{current_team: team, activity: activity, photo_ticks: ticks} = socket.assigns

    case MapSet.to_list(ticks) do
      [] ->
        {:noreply, put_flash(socket, :error, "Check the photos to delete first.")}

      ids ->
        {:ok, result} = DeleteActivityPhotos.call(team, activity, ids)
        {kind, text} = deleted_text(result)
        {:noreply, socket |> load() |> put_flash(kind, text)}
    end
  end

  def handle_event(event, params, socket), do: ActivityLive.handle_event(event, params, socket)

  defdelegate handle_info(message, socket), to: ActivityLive
  defdelegate render(assigns), to: ActivityLive

  defp deleted_text(%{deleted: deleted, kept: 0}),
    do: {:info, Format.count(deleted, one: "%d photo deleted.", many: "%d photos deleted.")}

  # The file store refused some: they stay waiting, to delete again.
  defp deleted_text(%{deleted: deleted, kept: kept}) do
    stayed =
      Format.count(kept,
        one: "%d photo did not delete. Delete it again.",
        many: "%d photos did not delete. Delete them again."
      )

    went = Format.count(deleted, one: "%d photo deleted.", many: "%d photos deleted.")
    {:error, if(deleted > 0, do: "#{went} #{stayed}", else: stayed)}
  end

  # Ids come from the browser; only waiting photos the tab shows stay checked.
  defp ticks(socket, params) do
    waiting =
      for %{status: :waiting} = photo <- socket.assigns.photos, into: MapSet.new(), do: photo.id

    params
    |> Map.get("photo_ids", [])
    |> Enum.flat_map(fn id ->
      case Integer.parse(id) do
        {id, ""} -> [id]
        _other -> []
      end
    end)
    |> MapSet.new()
    |> MapSet.intersection(waiting)
  end

  attr :activity, :map, required: true
  attr :team, :any, required: true
  attr :photos, :list, required: true, doc: "the photos the viewer sees, newest first"
  attr :ticks, :any, required: true, doc: "the waiting photos checked, by id"
  attr :team_admin?, :boolean, default: false
  attr :may_add?, :boolean, default: false, doc: "whether the viewer may add photos now"
  attr :now, :any, required: true

  @doc """
  The tab, drawn by Web.ActivityLive's page. A team admin's waiting photos are the
  checked tiles under Waiting; everything else the viewer sees is in the grid under the
  count, a member's own waiting ones with their badge.
  """
  def photos_tab(assigns) do
    waiting =
      if assigns.team_admin?, do: Enum.filter(assigns.photos, &(&1.status == :waiting)), else: []

    checked = Enum.count(waiting, &MapSet.member?(assigns.ticks, &1.id))

    assigns =
      assign(assigns,
        waiting: waiting,
        shown: assigns.photos -- waiting,
        checked: checked,
        delete_confirm: delete_confirm(checked)
      )

    ~H"""
    <section id="activity-photos">
      <section :if={@waiting != []} id="photos-waiting" class="mb-8">
        <h2 class="subheading">Waiting</h2>
        <p class="hint">Only team admins and the member who added one see it.</p>
        <.form
          for={%{}}
          id="photos-waiting-form"
          phx-change="tick-photos"
          phx-submit="accept-photos"
        >
          <div class="activity-photo-actions">
            <span id="photos-checked" class="hint">
              {Format.count(@checked, one: "%d checked", many: "%d checked")}
            </span>
            <.button
              id="photos-accept"
              variant={:success}
              disabled={@checked == 0}
              phx-disable-with="Accepting…"
            >
              {if @checked > 0, do: "Accept #{@checked}", else: "Accept"}
            </.button>
            <.button
              id="photos-delete"
              type="button"
              disabled={@checked == 0}
              phx-click="delete-photos"
              phx-disable-with="Deleting…"
              {@delete_confirm}
            >
              Delete
            </.button>
          </div>
          <ul id="photos-waiting-grid" class="activity-photo-grid">
            <li :for={photo <- @waiting} id={"photo-#{photo.id}"}>
              <Web.ActivityPhoto.tile
                id={"photo-#{photo.id}-tile"}
                photo={photo}
                team={@team}
                alt={alt(photo, @team, @now)}
              >
                <input
                  type="checkbox"
                  id={"photo-#{photo.id}-check"}
                  name="photo_ids[]"
                  value={photo.id}
                  checked={MapSet.member?(@ticks, photo.id)}
                />
              </Web.ActivityPhoto.tile>
              <label for={"photo-#{photo.id}-check"}>
                {Web.ActivityPhoto.added_text(photo, @team, @now)}
              </label>
            </li>
          </ul>
        </.form>
      </section>

      <.heading_row :if={@shown != []} id="photos-heading">
        <h2 id="photos-count" class="subheading">
          {Format.count(length(@shown), one: "%d photo", many: "%d photos")}
        </h2>
        <:action :if={@may_add?}>
          <.button id="photos-add" navigate={Web.ActivityPhoto.add_path(@team, @activity.id)}>
            Add photos
          </.button>
        </:action>
      </.heading_row>
      <ul :if={@shown != []} id="photos-grid" class="activity-photo-grid">
        <li :for={photo <- @shown} id={"photo-#{photo.id}"}>
          <Web.ActivityPhoto.tile
            id={"photo-#{photo.id}-tile"}
            photo={photo}
            team={@team}
            alt={alt(photo, @team, @now)}
          />
          <span class="block">{Web.ActivityPhoto.added_text(photo, @team, @now)}</span>
          <.badge :if={photo.status == :waiting} id={"photo-#{photo.id}-waiting"}>Waiting</.badge>
        </li>
      </ul>

      <div :if={@shown == []} id="photos-empty">
        <p class="hint">
          {if @may_add?, do: "No photos yet. Add the first.", else: "No photos yet."}
        </p>
        <.button
          :if={@may_add?}
          id="photos-add"
          navigate={Web.ActivityPhoto.add_path(@team, @activity.id)}
        >
          Add photos
        </.button>
      </div>
    </section>
    """
  end

  # What the photo shows, for someone who cannot see it: its caption, or who it is from.
  defp alt(%ActivityPhoto{caption: caption}, _team, _now) when is_binary(caption), do: caption

  defp alt(photo, team, now) do
    case Web.ActivityPhoto.added_by(photo, team, now) do
      nil -> "Photo"
      name -> "Photo from #{name}"
    end
  end

  # Delete's confirm (/styles/confirm-dialog#many): a photo has no name, so the count.
  # From 10 it waits on a check box.
  defp delete_confirm(0), do: %{}

  defp delete_confirm(count) do
    one? = count == 1
    photos = Format.count(count, one: "%d photo", many: "%d photos")

    Map.merge(
      %{
        "data-confirm" =>
          "Delete #{photos}? #{if one?, do: "It is", else: "They are"} gone for good.",
        "data-confirm-button" => if(one?, do: "Delete photo", else: "Delete photos"),
        "data-confirm-danger" => true
      },
      confirm_check(count, "I understand #{photos} are gone for good.")
    )
  end
end
