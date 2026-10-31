defmodule Web.Org.AdminsLive do
  use Web, :live_view_app_layout

  import Web.Components.OrgSettingsTabs

  alias App.Accounts
  alias App.Model.OrganizationAdmin

  # Organization settings › Organization admins (#512). Everyone sees who they are and
  # who the SAR Duty admins are. Only SAR Duty admins add and remove them, and the events
  # check that too, not just the markup.
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(page_title: "Organization settings · Organization admins")
      |> assign(sar_duty_admin?: socket.assigns.current_user.is_admin)
      |> assign(sar_duty_admins: Enum.sort(Accounts.admin_emails()), now: DateTime.utc_now())
      |> assign_admins()
      |> assign_form(OrganizationAdmin.build_changeset(%OrganizationAdmin{}))

    {:ok, socket}
  end

  defp assign_admins(socket),
    do:
      assign(socket,
        admins: OrganizationAdmin.get_for_organization(socket.assigns.current_organization)
      )

  defp assign_form(socket, changeset),
    do: assign(socket, :form, to_form(changeset, as: "organization_admin"))

  def render(assigns) do
    ~H"""
    <.org_settings_tabs organization={@current_organization} current={:admins} />
    <p class="lead max-w-3xl">
      They keep {@current_organization.short_name}'s settings and hours tags, and turn ID cards
      on or off for its teams. They see each team's totals, never its members.
    </p>
    <p class="max-w-3xl">
      Each logs in with their email. A SAR Duty site admin adds and removes them.
    </p>

    <.empty_state
      :if={@admins == []}
      id="no-organization-admins"
      title="No organization admins yet"
    >
      {if @sar_duty_admin?,
        do: "Add one with Add organization admin.",
        else: "A SAR Duty site admin adds them."}
    </.empty_state>
    <.table
      :if={@admins != []}
      id="organization-admins"
      rows={@admins}
      row_id={&"organization-admin-#{&1.id}"}
      class="table-striped"
    >
      <:col :let={admin} label="Email">
        <div><.email id={"organization-admin-#{admin.id}-email"} email={admin.email} /></div>
        <.hint :if={admin.reason}>{admin.reason}</.hint>
      </:col>
      <:col :let={admin} label="Last seen" class="whitespace-nowrap max-md:hidden">
        {Service.Format.days_ago(admin.last_seen_at, @now, @current_organization.timezone) ||
          "Never"}
      </:col>
      <:col :let={admin} label="Added" class="whitespace-nowrap max-md:hidden">
        {Service.Format.date_long(admin.inserted_at, @current_organization.timezone)}
        <.hint :if={@sar_duty_admin? && admin.added_by_user}>
          By {admin.added_by_user.email}
        </.hint>
      </:col>
      <:col :let={admin} :if={@sar_duty_admin?} label="" class="w-px">
        <.button
          id={"remove-organization-admin-#{admin.id}"}
          type="button"
          size={:sm}
          variant={:danger}
          phx-click="remove"
          phx-value-id={admin.id}
          data-confirm={"Remove #{admin.email}? They can no longer open #{@current_organization.short_name}'s pages."}
        >
          Remove
        </.button>
      </:col>
    </.table>

    <section :if={@sar_duty_admin?} id="add-organization-admin" class="mt-8 measure">
      <h2 class="heading">Add an organization admin</h2>
      <.form for={@form} id="organization-admin-form" phx-change="validate" phx-submit="add">
        <.input field={@form[:email]} type="email" label="Email">
          They log in with it at {Web.Endpoint.host()}/login. Tell them yourself: SAR Duty sends
          no email.
        </.input>
        <.input field={@form[:reason]} label="Why (optional)" placeholder="BCSARA's office manager" />
        <.form_actions>
          <.button variant={:success}>Add organization admin</.button>
        </.form_actions>
      </.form>
    </section>

    <section id="sar-duty-admins" class="mt-8 max-w-3xl">
      <h2 class="heading">SAR Duty site admins</h2>
      <p>
        They run SAR Duty, open every organization, and add or remove its teams and
        organization admins. Reach them at <.a href="mailto:support@sarduty.com">support@sarduty.com</.a>.
      </p>
      <ul id="sar-duty-admin-emails">
        <li :for={email <- @sar_duty_admins} class="break-all">{email}</li>
      </ul>
    </section>
    """
  end

  def handle_event("validate", %{"organization_admin" => params}, socket) do
    changeset =
      %OrganizationAdmin{organization_id: socket.assigns.current_organization.id}
      |> OrganizationAdmin.build_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("add", %{"organization_admin" => params}, socket) do
    %{current_organization: organization, current_user: user} = socket.assigns

    case OrganizationAdmin.add(organization, params, user) do
      {:ok, admin} ->
        socket =
          socket
          |> assign_admins()
          |> assign_form(OrganizationAdmin.build_changeset(%OrganizationAdmin{}))
          |> put_flash(:info, "Added #{admin.email}.")

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, refused())}
    end
  end

  def handle_event("remove", %{"id" => id}, socket) do
    %{current_organization: organization, current_user: user} = socket.assigns

    case OrganizationAdmin.remove(organization, id, user) do
      {:ok, admin} ->
        {:noreply, socket |> assign_admins() |> put_flash(:info, "Removed #{admin.email}.")}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, refused())}

      {:error, :not_found} ->
        {:noreply, socket |> assign_admins() |> put_flash(:error, "They were removed already.")}
    end
  end

  defp refused, do: "Only a SAR Duty site admin adds or removes organization admins."
end
