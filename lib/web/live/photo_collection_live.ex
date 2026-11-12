defmodule Web.PhotoCollectionLive do
  use Web, {:live_view_app_layout, access: :team, view_events: ["year"]}

  import Web.Components.MeYear
  import Web.Components.StatSwitch

  alias App.Model.ActivityPhoto
  alias App.Model.Member
  alias App.Model.MemberPhoto
  alias App.Model.PhotoAsk
  alias App.Model.Team
  alias App.Operation.AddActivityPhotos
  alias App.ViewData.TeamPhotos
  alias Service.Format
  alias Web.Components.Reply

  # Photos, /teams/:subdomain/photos: one page for everyone on the team (#645). Counts
  # filter it.
  #
  # The team's activity photos lead (#1033), while the team has them
  # (AddActivityPhotos.available?/1): Best of a year, the 24 accepted photos with the
  # most stars, with a Year menu; Activities, every accepted photo, newest first; Your
  # stars; and Yours, your own member photo and where it stands (#1029), then the
  # photos you added, waiting ones included. A tile opens the photo's page and names its
  # activity. Add photos asks which activity (Web.PhotoAddLive), for whoever may add to
  # one.
  #
  # A team admin also gets the members' photos (#1028). Members is every current
  # member's photo, as their ID card shows it; a member with none shows their initials
  # and a link to add one. Whether a member has a photo is `has_photo`, from the night's
  # check, so only members with one ask for theirs, as each scrolls into view. No photo
  # is the ones with none. Waiting lists the photos members added of themselves, oldest
  # first, each opening its check (#1029), then the photos that wait on an activity
  # (#1032), by activity, each opening its Photos tab. Ask for photos emails everyone
  # with no photo a link to add one (#1030).
  #
  # The page opens on Best of this year once the team has an accepted photo. Until then
  # it opens as before: Members for a team admin, and Yours for a member. On a team
  # with no activity photos a member has Yours alone, with no counts, and a team admin
  # the members' three.
  @photo_views [:best, :activities, :stars, :yours]
  @member_views [:members, :no_photo, :waiting]

  def mount(_params, _session, socket) do
    %{current_team: team, team_admin?: team_admin?, current_user: user} = socket.assigns
    if !Team.photos?(team), do: raise(Web.Status.NotFound)

    # Best of opens on this year, so the page's clock is one a test can set.
    now = Service.Clock.utc_now()
    activity_photos? = AddActivityPhotos.available?(team)
    # Who they are on the team: the member logged in, or a team admin's own member row.
    member = Reply.replier(socket.assigns, now)

    {:ok,
     assign(socket,
       page_title: "Photos",
       now: now,
       activity_photos?: activity_photos?,
       views: views(team_admin?, activity_photos?),
       who: %{member: member, user: user, team_admin?: team_admin?},
       may_add?:
         AddActivityPhotos.addable(team, %{team_admin?: team_admin?, member: member}, now) != []
     )}
  end

  defp views(true, true), do: @photo_views ++ @member_views
  defp views(true, false), do: @member_views
  defp views(false, true), do: @photo_views
  defp views(false, false), do: [:yours]

  def handle_params(params, _uri, socket) do
    %{current_team: team, team_admin?: team_admin?, views: views} = socket.assigns

    socket =
      socket
      |> assign(view: view!(params["view"], views, team, team_admin?), page: page(params["page"]))
      |> load_activity_photos(params)
      |> load_members()
      |> load_yours()

    {:noreply, socket}
  end

  # The view the URL names, which must be one of this person's. With none, Best of once
  # the team has an accepted photo, and until then the view the page had before.
  defp view!(nil, views, team, team_admin?) do
    cond do
      :best in views and TeamPhotos.any?(team) -> :best
      team_admin? -> :members
      true -> :yours
    end
  end

  defp view!(wanted, views, _team, _team_admin?),
    do: Enum.find(views, &(view_param(&1) == wanted)) || raise(Web.Status.NotFound)

  defp page(nil), do: 1

  defp page(param) do
    case Integer.parse(param) do
      {page, ""} when page > 0 -> page
      _other -> raise Web.Status.NotFound
    end
  end

  # The team's activity photos: the year Best of shows, its list, the counts, and the
  # page of the view that lists some.
  defp load_activity_photos(%{assigns: %{activity_photos?: false}} = socket, _params),
    do: assign(socket, counts: %{}, photos: nil, best: [], years: [], year: nil)

  defp load_activity_photos(socket, params) do
    %{current_team: team, current_user: user, who: who, view: view, now: now} = socket.assigns
    years = TeamPhotos.years(team, now)
    year = year!(params["year"], years)
    best = TeamPhotos.best(team, user, year)

    assign(socket,
      years: years,
      year: year,
      best: best,
      counts: team |> TeamPhotos.counts(user, who) |> Map.put(:best, length(best)),
      photos: photos(view, socket)
    )
  end

  defp photos(:activities, %{assigns: %{current_team: team, current_user: user, page: page}}),
    do: TeamPhotos.activities(team, user, page)

  defp photos(:stars, %{assigns: %{current_team: team, current_user: user, page: page}}),
    do: TeamPhotos.starred(team, user, page)

  defp photos(:yours, %{assigns: %{current_team: team, current_user: user} = assigns}),
    do: TeamPhotos.added(team, assigns.who, user, assigns.page)

  defp photos(_view, _socket), do: nil

  # A team admin's views of the members' photos: the members the grid shows, the photos
  # that wait, and the counts.
  defp load_members(%{assigns: %{team_admin?: false}} = socket), do: socket

  defp load_members(socket) do
    %{current_team: team, view: view, now: now} = socket.assigns
    members = Member.get_all_counted(team, now)
    without = Enum.reject(members, & &1.has_photo)

    socket
    |> assign(
      members: if(view == :no_photo, do: without, else: members),
      asks_by_member: team |> PhotoAsk.open_for_team() |> Map.new(&{&1.member_id, &1})
    )
    |> update(:counts, &Map.merge(&1, %{members: length(members), no_photo: length(without)}))
    |> load_waiting()
  end

  # What waits for a team admin: the photos members added of themselves, then an
  # activity's (#1032), by activity. Waiting counts both.
  defp load_waiting(socket) do
    %{current_team: team, now: now, activity_photos?: activity_photos?} = socket.assigns
    waiting = MemberPhoto.get_waiting(team, now)
    activity_waiting = if activity_photos?, do: ActivityPhoto.get_waiting(team), else: []

    socket
    |> assign(
      waiting: waiting,
      waiting_by_member: Map.new(waiting, &{&1.member_id, &1}),
      activity_waiting: by_activity(activity_waiting)
    )
    |> update(:counts, &Map.put(&1, :waiting, length(waiting) + length(activity_waiting)))
  end

  # Yours starts with the person's own member photo and where it stands. A team admin
  # with no member row has none.
  defp load_yours(%{assigns: %{view: :yours, who: %{member: %Member{} = member}}} = socket) do
    assign(socket,
      own: %{
        member: member,
        waiting: MemberPhoto.waiting_for_member(member),
        declined: MemberPhoto.declined_for_member(member)
      }
    )
  end

  defp load_yours(socket), do: assign(socket, own: nil)

  # Each activity with its waiting photos, in the order they came: `{activity, photos}`.
  defp by_activity(photos) do
    photos
    |> Enum.chunk_by(& &1.activity_id)
    |> Enum.map(fn [first | _] = group -> {first.activity, group} end)
  end

  def handle_event("year", %{"year" => year}, socket),
    do:
      {:noreply,
       push_patch(socket, to: view_path(socket.assigns.current_team, :best, year: year))}

  defp view_param(:no_photo), do: "no-photo"
  defp view_param(view), do: Atom.to_string(view)

  @doc "Photos, on the view it opens with."
  def path(team), do: ~p"/teams/#{team}/photos"

  @doc """
  The Photos page showing `view`: `:best`, `:activities`, `:stars`, `:yours`,
  `:members`, `:no_photo`, or `:waiting`. `year:` is Best of's year, and `page:` a
  list's page.
  """
  def view_path(team, view, opts \\ []) do
    query =
      [view: view_param(view)] ++ Keyword.reject(opts, fn {_key, value} -> is_nil(value) end)

    ~p"/teams/#{team}/photos?#{query}"
  end

  @doc "Add a photo, for `member` or with its Member box when nil."
  def add_path(team, nil), do: ~p"/teams/#{team}/photos/members/new"
  def add_path(team, member), do: ~p"/teams/#{team}/photos/members/new?#{[member: member.id]}"

  def render(assigns) do
    ~H"""
    <.heading_row>
      <h1 class="title">Photos</h1>
      <:action :if={@view in [:members, :no_photo, :waiting]}>
        <.button id="photo-ask" navigate={Web.PhotoAskLive.path(@current_team, nil)}>
          Ask for photos
        </.button>
        <.button id="photo-add" variant={:success} navigate={add_path(@current_team, nil)}>
          Add a photo
        </.button>
      </:action>
      <:action :if={@view not in [:members, :no_photo, :waiting] and @may_add?}>
        <.button id="photos-add" variant={:success} navigate={Web.PhotoAddLive.path(@current_team)}>
          Add photos
        </.button>
      </:action>
    </.heading_row>

    <.stat_switch :if={length(@views) > 1} id="photos-switch" label="Photos">
      <:view
        :for={view <- @views}
        id={"photos-view-#{view_param(view)}"}
        patch={view_path(@current_team, view)}
        current={@view == view}
        count={Map.fetch!(@counts, view)}
      >
        {view_label(view, @year)}
      </:view>
    </.stat_switch>

    <.best
      :if={@view == :best}
      photos={@best}
      year={@year}
      years={@years}
      team={@current_team}
    />
    <.photo_list
      :if={@view in [:activities, :stars]}
      view={@view}
      page={@photos}
      team={@current_team}
    />
    <.yours :if={@view == :yours} own={@own} page={@photos} team={@current_team} who={@who} />
    <.waiting
      :if={@view == :waiting}
      waiting={@waiting}
      activity_waiting={@activity_waiting}
      activity_photos?={@activity_photos?}
      team={@current_team}
      now={@now}
    />
    <.members
      :if={@view in [:members, :no_photo]}
      view={@view}
      members={@members}
      waiting_by_member={@waiting_by_member}
      asks_by_member={@asks_by_member}
      team={@current_team}
    />
    """
  end

  defp view_label(:best, year), do: "Best of #{year}"
  defp view_label(:activities, _year), do: "Activities"
  defp view_label(:stars, _year), do: "Your stars"
  defp view_label(:yours, _year), do: "Yours"
  defp view_label(:members, _year), do: "Members"
  defp view_label(:no_photo, _year), do: "No photo"
  defp view_label(:waiting, _year), do: "Waiting"

  attr :photos, :list, required: true
  attr :year, :integer, required: true
  attr :years, :list, required: true
  attr :team, :map, required: true

  # Best of a year: its Year menu, then the photos with the most stars.
  defp best(assigns) do
    ~H"""
    <.year_menu years={@years} year={@year} />
    <p :if={@photos != []} id="photos-best-hint" class="hint">
      The {TeamPhotos.best_limit()} photos with the most stars from {@year}, most first.
    </p>
    <p :if={@photos == []} id="photos-best-empty" class="hint">
      No stars yet for {@year}. Open a photo and star it.
    </p>
    <.photo_grid id="photos-best" photos={@photos} team={@team} />
    """
  end

  attr :view, :atom, required: true
  attr :page, :map, required: true
  attr :team, :map, required: true

  # Activities and Your stars: a page of accepted photos, newest first.
  defp photo_list(assigns) do
    ~H"""
    <p :if={@page.entries == []} id="photos-empty" class="hint">{empty_list(@view)}</p>
    <.photo_grid id="photos-list" photos={@page.entries} team={@team} />
    <.pagination
      class="my-4"
      paginated={@page}
      path_fn={fn [page: page] -> view_path(@team, @view, page: page) end}
    />
    """
  end

  defp empty_list(:activities), do: "No photos yet."
  defp empty_list(:stars), do: "You have not starred a photo yet."

  attr :id, :string, required: true
  attr :photos, :list, required: true
  attr :team, :map, required: true

  # Tiles of activity photos: each opens its page, shows its stars, and names its
  # activity, which opens the activity's Photos tab. A waiting one, under Yours, says so.
  defp photo_grid(assigns) do
    ~H"""
    <ul :if={@photos != []} id={@id} class="activity-photo-grid">
      <li :for={photo <- @photos} id={"photo-#{photo.id}"}>
        <Web.ActivityPhoto.tile
          id={"photo-#{photo.id}-tile"}
          photo={photo}
          team={@team}
          alt={Web.ActivityPhoto.alt(photo)}
          stars
        />
        <.a
          id={"photo-#{photo.id}-activity"}
          class="block"
          navigate={Web.ActivityPhoto.tab_path(@team, photo.activity_id)}
        >{photo.activity.title}</.a>
        <.badge :if={photo.status == :waiting} id={"photo-#{photo.id}-waiting"}>Waiting</.badge>
      </li>
    </ul>
    """
  end

  attr :own, :map, default: nil
  attr :page, :map, default: nil
  attr :team, :map, required: true
  attr :who, :map, required: true

  # Yours: the person's own member photo and where it stands, then the photos they
  # added to activities. While their own photo waits, the one their ID card still has
  # shows under it.
  defp yours(assigns) do
    ~H"""
    <section :if={@own} id="your-photo">
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
            <%!-- A team admin's Add a photo names the member: theirs needs no check. --%>
            <.a
              id="your-photo-add"
              navigate={add_path(@team, if(@who.team_admin?, do: @own.member))}
            >{if @own.waiting || @own.member.has_photo, do: "Change photo", else: "Add a photo"}</.a>
          </p>
        </div>
      </div>
    </section>

    <section :if={@own && @own.waiting && @own.member.has_photo} id="photo-on-card" class="mt-8">
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

    <section :if={@page && @page.entries != []} id="photos-added" class={@own && "mt-8"}>
      <h2 class="subheading">Photos you added</h2>
      <.photo_grid id="photos-list" photos={@page.entries} team={@team} />
      <.pagination
        class="my-4"
        paginated={@page}
        path_fn={fn [page: page] -> view_path(@team, :yours, page: page) end}
      />
    </section>
    <p :if={!@own and (!@page or @page.entries == [])} id="photos-empty" class="hint">
      No photos yet.
    </p>
    """
  end

  attr :waiting, :list, required: true
  attr :activity_waiting, :list, required: true
  attr :activity_photos?, :boolean, required: true
  attr :team, :map, required: true
  attr :now, :any, required: true

  # Waiting: members' own photos first, then each activity's.
  defp waiting(assigns) do
    ~H"""
    <.empty_state
      :if={@waiting == [] and @activity_waiting == []}
      id="no-photos-waiting"
      title="No photos waiting"
    >
      {if @activity_photos?,
        do: "Photos members add, of themselves or to an activity, show here for you to check.",
        else: "Photos members add of themselves show here for you to check."}
    </.empty_state>

    <%!-- Members' own photos first, under a heading once an activity's wait too. --%>
    <h2
      :if={@waiting != [] and @activity_waiting != []}
      id="photos-waiting-members"
      class="subheading"
    >
      Member photos
    </h2>
    <ul :if={@waiting != []} id="photos-waiting" class="photo-grid">
      <li :for={photo <- @waiting} id={"waiting-#{photo.id}"}>
        <.a
          id={"waiting-#{photo.id}-photo"}
          kind={:custom}
          class="photo-tile"
          navigate={Web.MemberPhoto.check_path(@team, photo)}
        ><img
          src={Web.MemberPhoto.waiting_path(@team, photo, :placed)}
          alt={"Photo from #{photo.member.name}"}
          loading="lazy"
          decoding="async"
        /></.a>
        <.a
          id={"waiting-#{photo.id}-name"}
          class="photo-tile-name"
          navigate={Web.MemberPhoto.check_path(@team, photo)}
        >{photo.member.name}</.a>
        <span class="hint">
          Added {Format.date_short(photo.inserted_at, @team.timezone)}
        </span>
      </li>
    </ul>

    <%!-- Then each activity's (#1032): its title opens its Photos tab, where a team
      admin accepts or deletes them. --%>
    <section
      :for={{activity, photos} <- @activity_waiting}
      id={"photos-waiting-activity-#{activity.id}"}
      class="mt-8"
    >
      <h2 class="subheading mb-0">
        <.a
          id={"photos-waiting-activity-#{activity.id}-link"}
          navigate={Web.ActivityPhoto.tab_path(@team, activity.id)}
        >{activity.title}</.a>
      </h2>
      <p class="hint mb-4">
        {Format.date_short(activity.started_at, @team.timezone)} · {Format.count(
          length(photos),
          one: "%d photo waiting",
          many: "%d photos waiting"
        )}
      </p>
      <ul class="activity-photo-grid">
        <li :for={photo <- photos} id={"activity-photo-#{photo.id}"}>
          <Web.ActivityPhoto.tile
            id={"activity-photo-#{photo.id}-tile"}
            photo={photo}
            team={@team}
            alt={Web.ActivityPhoto.alt(photo)}
          />
          {Web.ActivityPhoto.added_text(photo, @team, @now)}
        </li>
      </ul>
    </section>
    """
  end

  attr :view, :atom, required: true
  attr :members, :list, required: true
  attr :waiting_by_member, :map, required: true
  attr :asks_by_member, :map, required: true
  attr :team, :map, required: true

  # Members and No photo: every current member's photo, as their ID card shows it.
  defp members(assigns) do
    ~H"""
    <p :if={@view == :members} id="photos-members-hint" class="hint">
      Every current member's photo, as their ID card shows it.
    </p>
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
            src={Web.MemberPhoto.path(@team, member)}
            alt=""
            loading="lazy"
            decoding="async"
            data-hide-on-error
          />
        </span>
        <.a
          id={"photo-#{member.id}-name"}
          class="photo-tile-name"
          navigate={~p"/teams/#{@team}/members/#{member.id}/card"}
        >{member.name}</.a>
        <.a
          :if={waiting = @waiting_by_member[member.id]}
          id={"photo-#{member.id}-waiting"}
          kind={:custom}
          class="block"
          navigate={Web.MemberPhoto.check_path(@team, waiting)}
        ><.badge kind={:warning}>New photo waiting</.badge></.a>
        <%!-- Asked (#1030): the date, in place of the links. Their ID Card tab asks again. --%>
        <span
          :if={!@waiting_by_member[member.id] && @asks_by_member[member.id]}
          id={"photo-#{member.id}-asked"}
          class="hint block"
        >
          Asked {Format.month_day(@asks_by_member[member.id].asked_at, @team.timezone)}
        </span>
        <.a
          :if={add_links?(member, @waiting_by_member, @asks_by_member)}
          id={"photo-#{member.id}-add"}
          class="block"
          navigate={add_path(@team, member)}
        >Add a photo</.a>
        <.a
          :if={add_links?(member, @waiting_by_member, @asks_by_member)}
          id={"photo-#{member.id}-ask"}
          class="block"
          navigate={Web.PhotoAskLive.path(@team, member)}
        >Ask for a photo</.a>
      </li>
    </ul>
    """
  end

  # Add a photo and Ask for a photo, under a member with no photo, none waiting, and no
  # ask still open.
  defp add_links?(member, waiting, asks),
    do: !member.has_photo and !waiting[member.id] and !asks[member.id]

  defp empty_title(:members), do: "No current members"
  defp empty_title(:no_photo), do: "Every current member has a photo"

  defp empty_text(:members), do: "Members show here after the next refresh."
  defp empty_text(:no_photo), do: "Select Members to see them all."
end
