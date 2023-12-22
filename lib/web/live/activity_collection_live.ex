defmodule Web.ActivityCollectionLive do
  use Web, :live_view_app

  alias App.Model.Activity
  alias App.Repo
  alias App.ViewModel.ActivityFilterViewModel

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Activities")}
  end

  def handle_params(params, _uri, socket) do
    # TODO: Combine .validate and build_new_changeset into one function
    case ActivityFilterViewModel.validate(params) do
      {:ok, options} ->
        page_path_fn = fn n -> build_filter_path(socket, options |> Map.put(:page, n)) end
        page = fetch_page(socket.assigns.current_team.id, options)
        changeset = ActivityFilterViewModel.build_new_changeset(params)
        form = to_form(changeset, as: "form")

        socket =
          socket
          |> assign(page_path_fn: page_path_fn)
          |> assign(page: page)
          |> assign(form: form)

        {:noreply, socket}

      {:error, _} ->
        raise Web.Status.NotFound
    end
  end

  def fetch_page(team_id, data) do
    Activity
    |> Activity.scope(team_id: team_id)
    |> Activity.scope(activity: data.activity)
    |> Activity.scope(date: data.date)
    |> Activity.scope(q: data.q)
    |> Repo.paginate(%{page: data.page, page_size: data.limit})
  end

  def render(assigns) do
    ~H"""
    <div class="mb-p05 text-sm">
      <.a navigate={~p"/#{@current_team.subdomain}"}><%= @current_team.name %></.a>
    </div>
    <h1 class="title mb-p"><%= @page_title %></h1>
    <.form for={@form} phx-change="change">
      <div class="flex gap-4 items-center ">
        <.input field={@form[:q]} label="Search" />
        <.input
          label="Kind"
          field={@form[:activity]}
          type="select"
          options={ActivityFilterViewModel.activity_kinds()}
        />
        <.input
          label="Date"
          field={@form[:date]}
          type="select"
          options={ActivityFilterViewModel.date_kinds()}
        />
        <.input
          label="Limit"
          field={@form[:limit]}
          type="select"
          options={ActivityFilterViewModel.limits()}
        />
        <.a navigate={~p"/#{@current_team.subdomain}/activities"}>Reset</.a>
        <span class="grow"></span>
        <span class="">
          <%= @page.total_entries %> records
        </span>
      </div>
    </.form>

    <.pagination class="my-p" page={@page} page_path_fn={@page_path_fn} />

    <.table id="activity_collection" rows={@page.entries}>
      <:col :let={record} label="Activity">
        <.a navigate={~p"/#{@current_team.subdomain}/activities/#{record.id}"}>
          <.activity_title activity={record} /> #<%= record.ref_id %>
          <%= record.title %>
        </.a>
        <div class="hint break-words">
          <%= Service.StringHelpers.truncate(record.description, max_length: 120) %>
        </div>
        <.activity_tags activity={record} />
      </:col>
      <:col :let={record} label="Kind">
        <.activity_kind_badge activity={record} />
        <.activity_tracking_number_badge activity={record} />
      </:col>
      <:col :let={record} label="Date">
        <span class="whitespace-nowrap">
          <%= Calendar.strftime(record.started_at, "%x") %>
        </span>
      </:col>
    </.table>
    """
  end

  def handle_event("change", %{"form" => form_params}, socket) do
    case ActivityFilterViewModel.validate(form_params) do
      {:ok, options} ->
        {:noreply, push_patch(socket, to: build_filter_path(socket, options), replace: true)}

      {:error, _} ->
        raise Web.Status.NotFound
    end
  end

  def build_filter_path(socket, options) do
    query_params = build_query_params(options)
    ~p"/#{socket.assigns.current_team.subdomain}/activities?#{query_params}"
  end

  def build_query_params(options) do
    %{
      q: options.q,
      activity: options.activity,
      date: options.date,
      page: options.page,
      limit: options.limit
    }
    |> Map.reject(fn {k, v} -> k == :page && v == 1 end)
    |> Map.reject(fn {_, v} -> v == nil end)
  end
end
