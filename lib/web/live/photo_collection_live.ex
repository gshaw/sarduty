defmodule Web.PhotoCollectionLive do
  use Web, :live_view_app_layout

  import Web.Components.StatSwitch

  alias App.Model.Member
  alias App.Model.Team

  # Photos (#1028), /teams/:subdomain/photos: every current member's photo, as their ID
  # card shows it, for team admins. A member with none shows their initials and a link to
  # add one. The counts filter the grid. Whether a member has a photo is `has_photo`, from
  # the night's check, so only members with one ask for theirs, as each scrolls into view.
  @views [members: "Members", no_photo: "No photo"]

  def mount(_params, _session, socket) do
    if !Team.photos?(socket.assigns.current_team), do: raise(Web.Status.NotFound)
    {:ok, assign(socket, page_title: "Photos")}
  end

  def handle_params(params, _uri, socket) do
    view = Enum.find(Keyword.keys(@views), &(view_param(&1) == (params["view"] || "members")))
    if !view, do: raise(Web.Status.NotFound)

    members = Member.get_all_counted(socket.assigns.current_team, DateTime.utc_now())
    without = Enum.reject(members, & &1.has_photo)

    socket
    |> assign(view: view, counts: %{members: length(members), no_photo: length(without)})
    |> assign(members: if(view == :no_photo, do: without, else: members))
    |> then(&{:noreply, &1})
  end

  defp view_param(:members), do: "members"
  defp view_param(:no_photo), do: "no-photo"

  @doc "The Photos page showing `view`: `:members` or `:no_photo`."
  def view_path(team, :members), do: ~p"/teams/#{team}/photos"
  def view_path(team, view), do: ~p"/teams/#{team}/photos?#{[view: view_param(view)]}"

  @doc "Add a photo, for `member` or with its Member box when nil."
  def add_path(team, nil), do: ~p"/teams/#{team}/photos/members/new"
  def add_path(team, member), do: ~p"/teams/#{team}/photos/members/new?#{[member: member.id]}"

  def render(assigns) do
    assigns = assign(assigns, views: @views)

    ~H"""
    <.heading_row>
      <h1 class="title">Photos</h1>
      <:action>
        <.button id="photo-add" variant={:success} navigate={add_path(@current_team, nil)}>
          Add a photo
        </.button>
      </:action>
    </.heading_row>
    <p class="lead measure">Every current member's photo, as their ID card shows it.</p>

    <.stat_switch id="photos-switch" label="Photos">
      <:view
        :for={{view, label} <- @views}
        id={"photos-view-#{view_param(view)}"}
        patch={view_path(@current_team, view)}
        current={@view == view}
        count={Map.fetch!(@counts, view)}
      >
        {label}
      </:view>
    </.stat_switch>

    <.empty_state :if={@members == []} id="no-photos" title={empty_title(@view)}>
      {empty_text(@view)}
    </.empty_state>

    <ul :if={@members != []} id="photos" class="photo-grid">
      <li :for={member <- @members} id={"photo-#{member.id}"}>
        <%!-- Initials under the photo, so one that fails to load leaves them. --%>
        <span class={["photo-tile", !member.has_photo && "photo-tile-none"]}>
          <span aria-hidden="true">{Web.Navigation.initials(member.name)}</span>
          <img
            :if={member.has_photo}
            id={"photo-#{member.id}-image"}
            src={Web.MemberPhoto.path(@current_team, member)}
            alt=""
            loading="lazy"
            decoding="async"
            data-hide-on-error
          />
        </span>
        <.a
          id={"photo-#{member.id}-name"}
          class="photo-tile-name"
          navigate={~p"/teams/#{@current_team}/members/#{member.id}/card"}
        >{member.name}</.a>
        <.a
          :if={!member.has_photo}
          id={"photo-#{member.id}-add"}
          class="block"
          navigate={add_path(@current_team, member)}
        >Add a photo</.a>
      </li>
    </ul>
    """
  end

  defp empty_title(:members), do: "No current members"
  defp empty_title(:no_photo), do: "Every current member has a photo"

  defp empty_text(:members), do: "Members show here after the next refresh."
  defp empty_text(:no_photo), do: "Select Members to see them all."
end
