defmodule Web.ActivityTagsLive do
  use Web, :live_view_app_layout

  import Web.ActivityTemplateLive, only: [tags_to_add: 1]
  import Web.TemplateFormLive, only: [tag_search: 1]

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Tag
  alias App.Operation.ChangeActivityTags
  alias Web.TemplateFormLive

  # Changing an activity's tags (#323): which hours it counts for, and its other tags. The
  # tags are read from D4H as the page opens, and saving writes the whole list back.
  def mount(%{"id" => id}, _session, socket) do
    team = socket.assigns.current_team
    activity = Web.ActivityLive.fetch_activity(team, id)

    if activity.deleted_at do
      {:ok, Web.ActivityLive.leave_deleted(socket, activity)}
    else
      all_tags = Tag.get_all(team.id)

      socket =
        socket
        |> assign(page_title: "Change tags", activity: activity, all_tags: all_tags)
        |> assign(hours_tags: hours_tags(Activity.hours_tags(team), all_tags))
        |> assign(tag_q: "", tag_uses: Tag.use_counts(team.id, a_year_ago()))
        |> load_tags(ChangeActivityTags.current(team, activity))

      {:ok, socket}
    end
  end

  @doc """
  The team's hours tags that it has in D4H, as `%{kind => %Tag{}}`. `names` is
  `Activity.hours_tags/1`. A tag D4H doesn't have can't be chosen.
  """
  def hours_tags(names, all_tags) do
    for {kind, title} <- names,
        title,
        tag = Enum.find(all_tags, &(&1.title == title)),
        into: %{},
        do: {kind, tag}
  end

  @doc """
  Splits the activity's tag ids into its hours choice (`"primary"`, `"secondary"`,
  `"other"`, or `"none"`), its other tags, and the ids of tags the refresh hasn't copied yet. Primary
  wins over secondary, as on letters.
  """
  def split(start_ids, hours_tags, all_tags) do
    hours_ids = Map.new(hours_tags, fn {_kind, tag} -> {tag.d4h_tag_id, true} end)
    others = Enum.reject(start_ids, &Map.has_key?(hours_ids, &1))
    by_id = Map.new(all_tags, &{&1.d4h_tag_id, &1})

    tags =
      others
      |> Enum.flat_map(&List.wrap(by_id[&1]))
      |> Enum.sort_by(&TemplateFormLive.tag_sort/1)

    {hours_of(start_ids, hours_tags), tags, Enum.reject(others, &Map.has_key?(by_id, &1))}
  end

  defp hours_of(start_ids, hours_tags) do
    has? = fn kind -> hours_tags[kind] && hours_tags[kind].d4h_tag_id in start_ids end

    cond do
      has?.(:primary) -> "primary"
      has?.(:secondary) -> "secondary"
      has?.(:other) -> "other"
      true -> "none"
    end
  end

  @doc "The tag ids to save: the other tags, ones not copied yet, and the hours tag."
  def tag_ids(hours, tags, unknown_ids, hours_tags) do
    hours_id =
      for {kind, tag} <- hours_tags, Atom.to_string(kind) == hours, do: tag.d4h_tag_id

    Enum.map(tags, & &1.d4h_tag_id) ++ unknown_ids ++ hours_id
  end

  @doc """
  The hours choices the team's tags allow, for the select. Other is offered only when the
  team or its organization names an other tag (#323).
  """
  def hours_options(hours_tags) do
    [{"Primary", :primary}, {"Secondary", :secondary}, {"Other: no hours", :other}]
    |> Enum.filter(fn {_label, kind} -> hours_tags[kind] end)
    |> Enum.map(fn {label, kind} -> {label, Atom.to_string(kind)} end)
    |> Enum.concat([{"None", "none"}])
  end

  defp load_tags(socket, {:ok, start_ids}) do
    {hours, tags, unknown_ids} =
      split(start_ids, socket.assigns.hours_tags, socket.assigns.all_tags)

    assign(socket,
      start_ids: start_ids,
      hours: hours,
      tags: tags,
      unknown_ids: unknown_ids,
      published?: false,
      load_error: nil
    )
  end

  # D4H refuses tags on a published activity (#358), so the page says so in place of the form.
  defp load_tags(socket, :published) do
    socket
    |> assign(start_ids: nil, hours: "none", tags: [], unknown_ids: [], load_error: nil)
    |> assign(published?: true, activity: %{socket.assigns.activity | is_published: true})
  end

  defp load_tags(socket, {:error, text}) do
    assign(socket,
      start_ids: nil,
      hours: "none",
      tags: [],
      unknown_ids: [],
      published?: false,
      load_error: text
    )
  end

  defp a_year_ago, do: DateTime.add(DateTime.utc_now(), -365, :day)

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Activities" path={~p"/teams/#{@current_team}/activities"} />
      <:item label={@activity.ref_id} path={~p"/teams/#{@current_team}/activities/#{@activity.id}"} />
      <:item label="Change tags" />
    </.breadcrumbs>
    <h1 class="title">Change tags</h1>
    <p class="lead">{@activity.title}</p>

    <.banner
      :if={@load_error}
      id="tags-load-error"
      kind={:danger}
      title="SAR Duty cannot read this activity's tags"
    >
      <p>{@load_error}</p>
    </.banner>

    <.banner
      :if={@published?}
      id="tags-published"
      kind={:warning}
      title="This activity is published"
    >
      <p>
        {@service} does not let SAR Duty change a published activity's tags. Change them in {@service}.
      </p>
      <.button variant={:warning} href={D4H.activity_url(@current_team, @activity)}>
        Open {@service} activity
      </.button>
    </.banner>

    <div :if={!@load_error and !@published?} class="content-wrapper">
      <aside class="content-1/3">
        <section id="activity-tag-search">
          <h2 class="heading">Find a tag</h2>
          <.tag_search
            q={@tag_q}
            results={
              TemplateFormLive.tag_results(
                @all_tags,
                @tags ++ Map.values(@hours_tags),
                @tag_q,
                @tag_uses
              )
            }
          />
        </section>
      </aside>

      <main class="content-2/3">
        <.form for={%{}} id="activity-tags-form" phx-change="hours" phx-submit="save">
          <.input
            :if={@hours_tags != %{}}
            id="activity-hours"
            name="hours"
            type="select"
            label="Tax credit hours"
            value={@hours}
            options={hours_options(@hours_tags)}
          >
            Which hours the activity counts for on tax credit letters.
          </.input>

          <h2 class="heading mt-8">Other tags · {length(@tags)}</h2>
          <.tags_to_add :if={@tags != []} id="activity-tags" tags={@tags} />
          <p :if={@tags == []} id="activity-no-tags" class="hint mb-4">
            No other tags. Find tags to add.
          </p>

          <.form_actions>
            <.button id="activity-tags-save" variant={:success} phx-disable-with="Saving…">
              Save tags
            </.button>
          </.form_actions>
        </.form>
      </main>
    </div>
    """
  end

  def handle_event("search-tags", %{"tag_q" => q}, socket),
    do: {:noreply, assign(socket, tag_q: q)}

  def handle_event("add-tag", %{"id" => id}, socket) do
    tags = TemplateFormLive.add_tag(socket.assigns.tags, socket.assigns.all_tags, id)
    {:noreply, assign(socket, tags: tags)}
  end

  def handle_event("remove-tag", %{"id" => id}, socket),
    do: {:noreply, assign(socket, tags: TemplateFormLive.remove_tag(socket.assigns.tags, id))}

  def handle_event("hours", params, socket),
    do: {:noreply, assign(socket, hours: hours_param(params, socket))}

  def handle_event("save", params, socket) do
    %{current_team: team, current_user: user, activity: activity} = socket.assigns
    hours = hours_param(params, socket)

    ids =
      tag_ids(hours, socket.assigns.tags, socket.assigns.unknown_ids, socket.assigns.hours_tags)

    back = ~p"/teams/#{team}/activities/#{activity.id}"

    case ChangeActivityTags.call(
           team,
           activity,
           socket.assigns.start_ids,
           ids,
           user,
           DateTime.utc_now()
         ) do
      {:ok, %{status: :applied}} ->
        socket
        |> put_flash(:info, "Tags sent.")
        |> push_navigate(to: back)
        |> then(&{:noreply, &1})

      {:ok, row} ->
        {:noreply, put_flash(socket, :error, "Tags not saved. #{row.error}")}

      :unchanged ->
        {:noreply, push_navigate(socket, to: back)}

      {:error, text} ->
        {:noreply, put_flash(socket, :error, text)}
    end
  end

  # Only a choice the select offers; anything else keeps the page's.
  defp hours_param(params, socket) do
    allowed = socket.assigns.hours_tags |> hours_options() |> Enum.map(&elem(&1, 1))
    if params["hours"] in allowed, do: params["hours"], else: socket.assigns.hours
  end
end
