defmodule Web.TaxCreditLetterCollectionLive do
  use Web, :live_view_app_layout

  alias App.Mailer.TaxCreditLetterMailer
  alias App.Operation.CreateTaxCreditLetter
  alias App.ViewModel.TaxCreditLetterFilterViewModel

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    case TaxCreditLetterFilterViewModel.validate(params) do
      {:ok, filter_options, changeset} ->
        socket =
          socket
          |> assign(:page_title, "#{filter_options.year} Tax Credit Letters")
          |> assign(:filter_options, filter_options)
          |> assign(:form, to_form(changeset, as: "form"))
          |> assign(:path_fn, build_path_fn(socket.assigns.current_team, filter_options))
          |> assign_records()

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

    <h1 class="title mb-p">{@page_title}</h1>
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
      <span class="filter-form-count">{Enum.count(@records)} members</span>
    </.form>

    <.table
      id="member_collection"
      rows={@records}
      sort={@filter_options.sort}
      path_fn={@path_fn}
      class="w-full table-striped"
    >
      <:header_row>
        <th colspan="3"></th>
        <th colspan="3" class="text-center">SARVAC Hours</th>
        <th></th>
      </:header_row>
      <:col :let={record} label="ID" class="w-px" sorts={[{"↑", "id"}]}>
        {record.member.ref_id}
      </:col>
      <:col :let={record} label="Name" sorts={[{"↑", "name"}]}>
        <.a navigate={~p"/#{@current_team.subdomain}/members/#{record.member.id}"}>
          {record.member.name}
        </.a>
      </:col>
      <:col :let={record} label="Email">
        {record.member.email}
      </:col>

      <:col :let={record} label="Primary" class="w-px" align="right" sorts={[{"↓", "primary"}]}>
        <span class="label md:hidden">Primary</span>
        {record.primary_hours}
      </:col>
      <:col :let={record} label="Secondary" class="w-px" align="right" sorts={[{"↓", "secondary"}]}>
        <span class="label md:hidden">Secondary</span>
        {record.secondary_hours}
      </:col>
      <:col :let={record} label="Total" class="w-px" align="right" sorts={[{"↓", "total"}]}>
        <span class="label md:hidden">Total</span>
        {record.total_hours}
      </:col>
      <:col :let={record} label="Letter">
        <.record_actions record={record} current_team={@current_team} />
      </:col>
    </.table>
    """
  end

  defp record_actions(assigns) do
    ~H"""
    <%= if @record.tax_credit_letter_id do %>
      <.a navigate={
        ~p"/#{@current_team.subdomain}/tax-credit-letters/#{@record.tax_credit_letter_id}"
      }>
        <span class="font-mono text-sm">{@record.tax_credit_letter_ref_id}</span>
      </.a>
    <% else %>
      <button phx-click="create" value={@record.member.id} class="btn btn-success btn-sm">
        Create letter
      </button>
    <% end %>
    """
  end

  def handle_event("create", %{"value" => member_id}, socket) do
    tax_credit_letter =
      CreateTaxCreditLetter.call(
        team: socket.assigns.current_team,
        member_id: member_id,
        year: socket.assigns.filter_options.year
      )

    Task.start(fn -> TaxCreditLetterMailer.deliver_tax_credit_letter(tax_credit_letter) end)

    socket =
      socket
      |> assign_records()
      |> put_flash(:info, "Email sent to #{tax_credit_letter.member.email}")

    {:noreply, socket}
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

  defp assign_records(socket) do
    records =
      TaxCreditLetterFilterViewModel.find_all(
        socket.assigns.current_team,
        socket.assigns.filter_options
      )

    assign(socket, :records, records)
  end

  defp build_path_fn(team, filter_options) do
    fn changed_options ->
      case changed_options do
        :reset ->
          build_filter_path(team, %TaxCreditLetterFilterViewModel{})

        _ ->
          build_filter_path(team, Map.merge(filter_options, Map.new(changed_options)))
      end
    end
  end

  defp build_filter_path(team, filter_options) do
    query_params = Service.PathHelpers.build_filter_query_params(filter_options)
    ~p"/#{team.subdomain}/tax-credit-letters?#{query_params}"
  end
end
