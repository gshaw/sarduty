defmodule Web.PhotoCollectionLive do
  use Web, {:live_view_app_layout, access: :team}

  import Web.Components.StatSwitch

  alias App.Model.Member
  alias App.Model.MemberPhoto
  alias App.Model.Team
  alias Service.Format

  # Photos, /teams/:subdomain/photos: one page for everyone on the team (#645).
  #
  # A team admin sees every current member's photo, as their ID card shows it (#1028). A
  # member with none shows their initials and a link to add one. The counts filter the
  # grid. Whether a member has a photo is `has_photo`, from the night's check, so only
  # members with one ask for theirs, as each scrolls into view. Waiting lists the photos
  # members added of themselves, oldest first, each opening its check (#1029), and a
  # member with one waiting has a badge in the grid that opens it too.
  #
  # A member sees only their own part (#1029): their photo and where it stands, with Add
  # a photo or Change photo. None of the team's views open for them. A team admin who is
  # also a member sees the team's views.
  @views [members: "Members", waiting: "Waiting", no_photo: "No photo"]

  def mount(_params, _session, socket) do
    if !Team.photos?(socket.assigns.current_team), do: raise(Web.Status.NotFound)
    {:ok, assign(socket, page_title: "Photos")}
  end

  def handle_params(params, _uri, %{assigns: %{team_admin?: true}} = socket) do
    wanted = params["view"] || "members"
    view = @views |> Keyword.keys() |> Enum.find(&(view_param(&1) == wanted))
    if !view, do: raise(Web.Status.NotFound)

    {:noreply, socket |> assign(view: view, own: nil) |> load_team()}
  end

  # A member's own part. A URL that names one of the team's views is not found.
  def handle_params(params, _uri, socket) do
    if params["view"], do: raise(Web.Status.NotFound)
    member = socket.assigns.current_member

    own = %{
      member: member,
      waiting: MemberPhoto.waiting_for_member(member),
      declined: MemberPhoto.declined_for_member(member)
    }

    {:noreply, assign(socket, own: own)}
  end

  # The team's views: the members the grid shows, the photos that wait, and the counts.
  defp load_team(socket) do
    %{current_team: team, view: view} = socket.assigns
    now = DateTime.utc_now()
    members = Member.get_all_counted(team, now)
    without = Enum.reject(members, & &1.has_photo)
    waiting = MemberPhoto.get_waiting(team, now)

    assign(socket,
      counts: %{members: length(members), waiting: length(waiting), no_photo: length(without)},
      members: if(view == :no_photo, do: without, else: members),
      waiting: waiting,
      waiting_by_member: Map.new(waiting, &{&1.member_id, &1})
    )
  end

  defp view_param(:no_photo), do: "no-photo"
  defp view_param(view), do: Atom.to_string(view)

  @doc "The Photos page showing `view`: `:members`, `:waiting`, or `:no_photo`."
  def view_path(team, :members), do: ~p"/teams/#{team}/photos"
  def view_path(team, view), do: ~p"/teams/#{team}/photos?#{[view: view_param(view)]}"

  @doc "Add a photo, for `member` or with its Member box when nil."
  def add_path(team, nil), do: ~p"/teams/#{team}/photos/members/new"
  def add_path(team, member), do: ~p"/teams/#{team}/photos/members/new?#{[member: member.id]}"

  def render(%{own: %{}} = assigns) do
    ~H"""
    <h1 class="title">Photos</h1>
    <.yours own={@own} team={@current_team} />
    """
  end

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

    <%= if @view == :waiting do %>
      <.empty_state :if={@waiting == []} id="no-photos-waiting" title="No photos waiting">
        Photos members add of themselves show here for you to check.
      </.empty_state>

      <ul :if={@waiting != []} id="photos-waiting" class="photo-grid">
        <li :for={photo <- @waiting} id={"waiting-#{photo.id}"}>
          <.a
            id={"waiting-#{photo.id}-photo"}
            kind={:custom}
            class="photo-tile"
            navigate={Web.MemberPhoto.check_path(@current_team, photo)}
          ><img
            src={Web.MemberPhoto.waiting_path(@current_team, photo, :placed)}
            alt={"Photo from #{photo.member.name}"}
            loading="lazy"
            decoding="async"
          /></.a>
          <.a
            id={"waiting-#{photo.id}-name"}
            class="photo-tile-name"
            navigate={Web.MemberPhoto.check_path(@current_team, photo)}
          >{photo.member.name}</.a>
          <span class="hint">
            Added {Format.date_short(photo.inserted_at, @current_team.timezone)}
          </span>
        </li>
      </ul>
    <% else %>
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
            :if={waiting = @waiting_by_member[member.id]}
            id={"photo-#{member.id}-waiting"}
            kind={:custom}
            class="block"
            navigate={Web.MemberPhoto.check_path(@current_team, waiting)}
          ><.badge kind={:warning}>New photo waiting</.badge></.a>
          <.a
            :if={!member.has_photo and !@waiting_by_member[member.id]}
            id={"photo-#{member.id}-add"}
            class="block"
            navigate={add_path(@current_team, member)}
          >Add a photo</.a>
        </li>
      </ul>
    <% end %>
    """
  end

  attr :own, :map, required: true
  attr :team, :map, required: true

  # A member's own photo and where it stands. While one waits, the photo their ID card
  # still has shows under it.
  defp yours(assigns) do
    ~H"""
    <section id="your-photo">
      <h2 class="subheading">Your photo</h2>
      <div class="photo-yours">
        <span :if={@own.waiting} class="photo-tile">
          <img
            id="your-photo-waiting"
            src={Web.MemberPhoto.waiting_path(@team, @own.waiting, :placed)}
            alt="The photo you added"
          />
        </span>
        <span :if={!@own.waiting and @own.member.has_photo} class="photo-tile">
          <span aria-hidden="true">{Web.Navigation.initials(@own.member.name)}</span>
          <img
            id="your-photo-now"
            src={Web.MemberPhoto.path(@team, @own.member)}
            alt="Your photo"
            data-hide-on-error
          />
        </span>
        <div>
          <div :if={@own.waiting} id="your-photo-status">
            <p>
              <.badge>Waiting</.badge>
            </p>
            <p>
              Added {Format.date_short(@own.waiting.inserted_at, @team.timezone)}. A team admin checks it before your ID card shows it.
            </p>
          </div>
          <p :if={!@own.waiting and !@own.member.has_photo} id="your-photo-none">
            You have no photo yet.
          </p>
          <p :if={@own.declined} id="your-photo-declined">
            Declined {Format.date_short(@own.declined.decided_at, @team.timezone)}: {Web.MemberPhoto.reason(
              @own.declined
            )}.
          </p>
          <p class="action">
            <.a id="your-photo-add" navigate={add_path(@team, nil)}>{if @own.waiting ||
                                                                          @own.member.has_photo,
                                                                        do: "Change photo",
                                                                        else: "Add a photo"}</.a>
          </p>
        </div>
      </div>
    </section>

    <section :if={@own.waiting && @own.member.has_photo} id="photo-on-card" class="mt-8">
      <h2 class="subheading">On your ID card now</h2>
      <span class="photo-tile photo-tile-small">
        <span aria-hidden="true">{Web.Navigation.initials(@own.member.name)}</span>
        <img
          id="photo-on-card-image"
          src={Web.MemberPhoto.path(@team, @own.member)}
          alt="The photo on your ID card now"
          data-hide-on-error
        />
      </span>
    </section>
    """
  end

  defp empty_title(:members), do: "No current members"
  defp empty_title(:no_photo), do: "Every current member has a photo"

  defp empty_text(:members), do: "Members show here after the next refresh."
  defp empty_text(:no_photo), do: "Select Members to see them all."
end
