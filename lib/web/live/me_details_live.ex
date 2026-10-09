defmodule Web.MeDetailsLive do
  use Web, :live_view_narrow_layout

  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Operation.SaveOwnDetails
  alias App.ViewModel.MemberDetailsViewModel

  # A member changes their own address and emergency contacts (#156),
  # /teams/:subdomain/me/details. The form shows what D4H holds now, and saving sends the
  # change straight to D4H. `member` comes from the login, never from the URL.
  def mount(_params, _session, socket) do
    member = socket.assigns.member

    socket =
      socket
      |> assign(:page_title, "Your contact details")
      |> assign(:contacts?, "primary_emergency_contact" in SaveOwnDetails.fields(member.team))
      |> load()

    {:ok, socket}
  end

  defp load(socket) do
    case SaveOwnDetails.load(socket.assigns.member) do
      {:ok, details} ->
        form = MemberDetailsViewModel.from_details(details)
        socket |> assign(details: details, error: nil) |> assign_form(form, %{})

      {:error, text} ->
        assign(socket, details: nil, error: text, form: nil)
    end
  end

  defp assign_form(socket, form, params) do
    changeset = MemberDetailsViewModel.changeset(form, params)
    assign(socket, form_data: form, form: to_form(changeset, as: "details"))
  end

  def handle_event("validate", %{"details" => params}, socket) do
    changeset =
      socket.assigns.form_data
      |> MemberDetailsViewModel.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "details"))}
  end

  # The login is checked again, in case the team turned member logins off since the page
  # opened.
  def handle_event("save", %{"details" => params}, socket) do
    %{current_user: user, member: member} = socket.assigns

    case Member.get_login(user.email, member.id, DateTime.utc_now()) do
      nil -> {:noreply, redirect(socket, to: ~p"/")}
      member -> {:noreply, save(socket, member, params)}
    end
  end

  defp save(socket, member, params) do
    %{current_user: user, details: details, form_data: form} = socket.assigns

    with {:ok, values} <- MemberDetailsViewModel.validate(form, params),
         values = MemberDetailsViewModel.to_values(values),
         {:ok, _result} <- SaveOwnDetails.call(member, user, details, values, DateTime.utc_now()) do
      socket
      |> put_flash(:info, "Your contact details are saved in #{service(member)}.")
      |> push_navigate(to: ~p"/teams/#{member.team}/me")
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        assign(socket, form: to_form(changeset, as: "details"))

      {:error, text} ->
        put_flash(socket, :error, text)
    end
  end

  defp service(member), do: D4H.service_name(member.team)

  def render(assigns) do
    ~H"""
    <div>
      <.back_link navigate={~p"/teams/#{@member.team}/me"}>{@member.team.name}</.back_link>
      <h1 class="heading">Your contact details</h1>
      <p class="lead">
        Saving changes them in {service(@member)}, where your team admins see them.
      </p>

      <.banner :if={@error} id="details-error" kind={:warning} title="Your details did not load">
        {@error}
      </.banner>

      <.form
        :if={@form}
        for={@form}
        id="details-form"
        phx-change="validate"
        phx-submit="save"
      >
        <.error_summary form={@form} />
        <.input field={@form[:address]} type="textarea" rows="4" label="Mailing address" />

        <%= if @contacts? do %>
          <h2 class="subheading mt-8">Emergency contact</h2>
          <.contact_fields
            form={@form}
            fields={[
              :contact1_name,
              :contact1_relation,
              :contact1_primary_phone,
              :contact1_secondary_phone
            ]}
          />
          <h2 class="subheading mt-8">Second emergency contact (optional)</h2>
          <.contact_fields
            form={@form}
            fields={[
              :contact2_name,
              :contact2_relation,
              :contact2_primary_phone,
              :contact2_secondary_phone
            ]}
          />
        <% end %>

        <.form_actions>
          <.button variant={:success} phx-disable-with="Saving…">Save details</.button>
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
