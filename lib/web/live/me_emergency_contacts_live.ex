defmodule Web.MeEmergencyContactsLive do
  use Web, {:live_view_app_layout, access: :member, view_events: ["validate"]}

  import Web.MemberLogin

  alias App.Operation.SaveOwnDetails
  alias App.ViewModel.MemberDetailsViewModel

  # Change emergency contacts (#156), /teams/:subdomain/me/emergency-contacts: the
  # member's two contacts, the second optional. The form shows the member's copy, which
  # the sync keeps (#423), and saving sends the change straight to D4H. A team admin
  # viewing as the member (#425) sees the page with saving turned off.
  def mount(_params, _session, socket) do
    form = MemberDetailsViewModel.from_member(socket.assigns.current_member)

    socket =
      socket
      |> assign(:page_title, "Change emergency contacts")
      |> assign(:form_data, form)
      |> assign(:form, to_form(MemberDetailsViewModel.changeset(form), as: "details"))

    {:ok, socket}
  end

  def handle_event("validate", %{"details" => params}, socket) do
    changeset =
      socket.assigns.form_data
      |> MemberDetailsViewModel.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "details"))}
  end

  def handle_event("save", %{"details" => params}, socket),
    do: {:noreply, with_login(socket, &save(socket, &1, params))}

  defp save(socket, member, params) do
    %{current_user: user, form_data: form} = socket.assigns

    with {:ok, values} <- MemberDetailsViewModel.validate(form, params),
         values =
           values
           |> MemberDetailsViewModel.to_values()
           |> Map.take(["primary_emergency_contact", "secondary_emergency_contact"]),
         {:ok, _result} <- SaveOwnDetails.call(member, user, values, DateTime.utc_now()) do
      socket
      |> put_flash(:info, "Your emergency contacts are saved.")
      |> push_navigate(to: ~p"/teams/#{member.team}/me")
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        assign(socket, form: to_form(changeset, as: "details"))

      {:error, text} ->
        put_flash(socket, :error, text)
    end
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Your membership" path={~p"/teams/#{@current_member.team}/me"} />
      <:item label="Change emergency contacts" />
    </.breadcrumbs>
    <div class="measure">
      <h1 class="title">Change emergency contacts</h1>
      <p class="lead">Changes go to your team's records, where your team admins see them.</p>
      <.form for={@form} id="contacts-form" phx-change="validate" phx-submit="save">
        <.error_summary form={@form} />
        <h2 class="subheading">Emergency contact</h2>
        <.contact_fields
          form={@form}
          fields={[
            :contact1_name,
            :contact1_relation,
            :contact1_primary_phone,
            :contact1_secondary_phone
          ]}
        />
        <h2 class="subheading mt-6">Second emergency contact (optional)</h2>
        <.contact_fields
          form={@form}
          fields={[
            :contact2_name,
            :contact2_relation,
            :contact2_primary_phone,
            :contact2_secondary_phone
          ]}
        />
        <.form_actions>
          <.button variant={:success} phx-disable-with="Saving…" disabled={@viewing_as != nil}>
            Save contacts
          </.button>
          <.button navigate={~p"/teams/#{@current_member.team}/me"}>Cancel</.button>
        </.form_actions>
      </.form>
    </div>
    """
  end

  attr :form, :map, required: true
  attr :fields, :list, required: true, doc: "name, relation, phone, and other phone"

  defp contact_fields(assigns) do
    [name, relation, phone, other_phone] = assigns.fields
    assigns = assign(assigns, name: name, relation: relation, phone: phone, other: other_phone)

    ~H"""
    <.input field={@form[@name]} label="Name" />
    <.input field={@form[@relation]} label="Relationship">
      How they know you, like Partner or Parent.
    </.input>
    <.input field={@form[@phone]} type="tel" label="Phone" />
    <.input field={@form[@other]} type="tel" label="Other phone (optional)" />
    """
  end
end
