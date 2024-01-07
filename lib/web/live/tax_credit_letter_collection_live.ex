defmodule Web.TaxCreditLetterCollectionLive do
  use Web, :live_view_app_layout

  alias App.ViewModel.TaxCreditLetterFilterViewModel

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Tax Credit Letters")}
  end

  def handle_params(params, _uri, socket) do
    case TaxCreditLetterFilterViewModel.validate(params) do
      {:ok, filter_options, changeset} ->
        current_team = socket.assigns.current_team

        socket =
          socket
          |> assign(:sort, filter_options.sort)
          |> assign(:year, filter_options.year)
          |> assign(:records, fetch_records(current_team, filter_options))
          |> assign(:path_fn, build_path_fn(current_team, filter_options))
          |> assign(:form, to_form(changeset, as: "form"))

        {:noreply, socket}

      {:error, _} ->
        raise Web.Status.NotFound
    end
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
      <:item label={@page_title} />
    </.breadcrumbs>

    <span class="badge badge-warning">Under Construction</span>
    <h1 class="title mb-p"><%= @page_title %></h1>
    <.form for={@form} phx-change="change" phx-submit="change" class="filter-form">
      <.input
        label="Year"
        field={@form[:year]}
        type="select"
        options={TaxCreditLetterFilterViewModel.years()}
      />
      <.input field={@form[:q]} label="Search" />
      <.input
        label="Sort"
        field={@form[:sort]}
        type="select"
        options={TaxCreditLetterFilterViewModel.sort_kinds()}
      />
      <.input
        label="Cutoff"
        field={@form[:cutoff]}
        type="select"
        options={TaxCreditLetterFilterViewModel.cutoffs()}
      />
      <.a class="filter-form-reset" navigate={@path_fn.(:reset)}>Reset</.a>
      <span class="filter-form-count"><%= Enum.count(@records) %> members</span>
    </.form>

    <.table
      id="member_collection"
      rows={@records}
      sort={@sort}
      path_fn={@path_fn}
      class="w-full table-striped"
    >
      <:header_row>
        <th colspan="3"></th>
        <th colspan="3" class="text-center">SARVAC Hours</th>
      </:header_row>
      <:col :let={record} label="" class="w-px">
        <.input field={@form[:ids]} type="checkbox" value={record.member.id} />
      </:col>
      <:col :let={record} label="ID" class="w-px" align="right" sorts={[{"↑", "id"}]}>
        <%= record.member.ref_id %>
      </:col>
      <:col :let={record} label="Name" sorts={[{"↑", "name"}]}>
        <.a navigate={~p"/#{@current_team.subdomain}/members/#{record.member.id}"}>
          <%= record.member.name %>
        </.a>
      </:col>

      <:col :let={record} label="Primary" class="w-px" align="right" sorts={[{"↓", "primary"}]}>
        <span class="label md:hidden">Hours</span>
        <%= record.primary_hours %>
      </:col>
      <:col :let={record} label="Secondary" class="w-px" align="right" sorts={[{"↓", "secondary"}]}>
        <span class="label md:hidden">Hours</span>
        <%= record.secondary_hours %>
      </:col>
      <:col :let={record} label="Total" class="w-px" align="right" sorts={[{"↓", "total"}]}>
        <span class="label md:hidden">Hours</span>
        <%= record.total_hours %>
      </:col>
    </.table>
    """
  end

  def handle_event("change", %{"form" => form_params}, socket) do
    case TaxCreditLetterFilterViewModel.validate(form_params) do
      {:ok, filter_options, _changeset} ->
        path = build_filter_path(socket.assigns.current_team, filter_options)
        {:noreply, push_patch(socket, to: path, replace: true)}

      {:error, _} ->
        raise Web.Status.NotFound
    end
  end

  def fetch_records(team, filter_options) do
    TaxCreditLetterFilterViewModel.fetch_all(team, filter_options)
  end

  def build_path_fn(team, filter_options) do
    fn changed_options ->
      case changed_options do
        :reset ->
          build_filter_path(team, %TaxCreditLetterFilterViewModel{})

        _ ->
          build_filter_path(team, Map.merge(filter_options, Map.new(changed_options)))
      end
    end
  end

  def build_filter_path(team, filter_options) do
    query_params = Service.PathHelpers.build_filter_query_params(filter_options)
    ~p"/#{team.subdomain}/tax-credit-letters?#{query_params}"
  end
end
