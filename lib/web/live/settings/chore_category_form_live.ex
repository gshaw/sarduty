defmodule Web.Settings.ChoreCategoryFormLive do
  use Web, :live_view_app_layout

  import Web.ActivityTemplateLive, only: [tags_to_add: 1]
  import Web.TemplateFormLive, only: [tag_search: 1]

  alias App.Model.Activity
  alias App.Model.ChoreCategory
  alias App.Model.Tag
  alias App.Operation.SaveChoreCategory
  alias Web.ActivityTagsLive
  alias Web.Settings.ChoreCategoryCollectionLive
  alias Web.TemplateFormLive

  # Adding and changing a chore category (#341): its name, which hours its chores count
  # for, and the other tags its D4H events get. The layout is an activity's Change tags.
  def mount(params, _session, socket) do
    team = socket.assigns.current_team
    if !team.member_logins, do: raise(Web.Status.NotFound)

    category = if id = params["id"], do: ChoreCategory.find!(team, id)
    all_tags = Tag.get_all(team.id)

    socket =
      socket
      |> assign(category: category, all_tags: all_tags)
      |> assign(tags: if(category, do: ChoreCategory.tags(category), else: []))
      |> assign(
        hours_tags: team |> Activity.hours_tags() |> ActivityTagsLive.hours_tags(all_tags)
      )
      |> assign(tag_q: "", tag_uses: Tag.use_counts(team.id, a_year_ago()))
      |> assign(page_title: if(category, do: "Change category", else: "Add category"))
      |> assign_form(ChoreCategory.build_changeset(category || %ChoreCategory{}))

    {:ok, socket}
  end

  defp assign_form(socket, changeset),
    do: assign(socket, :form, to_form(changeset, as: "category"))

  defp a_year_ago, do: DateTime.add(DateTime.utc_now(), -365, :day)

  defp hours_options,
    do:
      for(
        kind <- [:primary, :secondary],
        do: {ChoreCategoryCollectionLive.hours_label(kind), kind}
      )

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Chore categories" path={~p"/teams/#{@current_team}/settings/chore-categories"} />
      <:item label={if @category, do: @category.title, else: @page_title} />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>
    <p :if={@category} class="lead">{@category.title}</p>

    <div class="content-wrapper">
      <aside class="content-1/3">
        <section id="chore-category-tag-search">
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
        <.form for={@form} id="chore-category-form" phx-change="validate" phx-submit="save">
          <.error_summary form={@form} />
          <.input field={@form[:title]} label="Name">Such as "Equipment maintenance".</.input>
          <.input
            field={@form[:hours]}
            type="select"
            label="SARVAC hours"
            prompt="Select hours"
            options={hours_options()}
          >
            Which hours these chores count for on tax credit letters.
          </.input>

          <h2 class="heading mt-8">Other tags · {length(@tags)}</h2>
          <.tags_to_add :if={@tags != []} id="chore-category-tags" tags={@tags} />
          <p :if={@tags == []} id="chore-category-no-tags" class="hint mb-4">
            No other tags. Find tags to add.
          </p>

          <.warning_text :if={@category} class="mt-4">
            Tag changes go on activities sent from now on. Activities already in D4H keep their tags.
          </.warning_text>

          <.form_actions>
            <.button id="chore-category-save" variant={:success}>
              {if @category, do: "Save category", else: "Add category"}
            </.button>
            <.button navigate={~p"/teams/#{@current_team}/settings/chore-categories"}>
              Cancel
            </.button>
            <:trailing :if={@category}>
              <.button
                :if={!ChoreCategory.archived?(@category)}
                id="chore-category-archive"
                type="button"
                phx-click="archive"
              >
                Archive category
              </.button>
              <.button
                :if={ChoreCategory.archived?(@category)}
                id="chore-category-restore"
                type="button"
                phx-click="restore"
              >
                Restore category
              </.button>
            </:trailing>
          </.form_actions>
        </.form>
      </main>
    </div>
    """
  end

  def handle_event("validate", params, socket) do
    changeset =
      (socket.assigns.category || %ChoreCategory{})
      |> ChoreCategory.build_changeset(params["category"] || %{})
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", params, socket) do
    %{current_team: team, category: category, tags: tags} = socket.assigns

    case SaveChoreCategory.save(
           team,
           category,
           params["category"] || %{},
           Enum.map(tags, & &1.id)
         ) do
      {:ok, saved} ->
        socket
        |> put_flash(:info, "Saved the #{saved.title} category.")
        |> push_navigate(to: ~p"/teams/#{team}/settings/chore-categories")
        |> then(&{:noreply, &1})

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("archive", _params, socket),
    do: set_archived(socket, DateTime.utc_now(), "Archived")

  def handle_event("restore", _params, socket),
    do: set_archived(socket, nil, "Restored")

  def handle_event("search-tags", %{"tag_q" => q}, socket),
    do: {:noreply, assign(socket, tag_q: q)}

  def handle_event("add-tag", %{"id" => id}, socket) do
    tags = TemplateFormLive.add_tag(socket.assigns.tags, socket.assigns.all_tags, id)
    {:noreply, assign(socket, tags: tags)}
  end

  def handle_event("remove-tag", %{"id" => id}, socket),
    do: {:noreply, assign(socket, tags: TemplateFormLive.remove_tag(socket.assigns.tags, id))}

  defp set_archived(socket, archived_at, verb) do
    %{current_team: team, category: category} = socket.assigns
    {:ok, category} = SaveChoreCategory.archive(team, category, archived_at)

    socket
    |> put_flash(:info, "#{verb} the #{category.title} category.")
    |> push_navigate(to: ~p"/teams/#{team}/settings/chore-categories")
    |> then(&{:noreply, &1})
  end
end
