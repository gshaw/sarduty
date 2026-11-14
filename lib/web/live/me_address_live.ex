defmodule Web.MeAddressLive do
  use Web, {:live_view_app_layout, access: :member, view_events: ["validate"]}

  import Web.MemberLogin

  alias App.Operation.SaveOwnDetails
  alias App.ViewModel.MemberDetailsViewModel

  # Change mailing address (#156), /teams/:subdomain/me/address. The form shows the
  # member's copy, which the sync keeps (#423), and saving sends the change straight to
  # D4H. A team admin viewing as the member (#425) sees the page with saving turned off.
  def mount(_params, _session, socket) do
    form = MemberDetailsViewModel.from_member(socket.assigns.current_member)

    socket =
      socket
      |> assign(:page_title, "Change mailing address")
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
         values = values |> MemberDetailsViewModel.to_values() |> Map.take(["address"]),
         {:ok, _result} <- SaveOwnDetails.call(member, user, values, DateTime.utc_now()) do
      socket
      |> put_flash(:info, "Your mailing address is saved.")
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
      <:item label="Change mailing address" />
    </.breadcrumbs>
    <div class="measure">
      <h1 class="title">Change mailing address</h1>
      <p class="lead">Changes go to your team's records, where your team admins see them.</p>
      <.form for={@form} id="address-form" phx-change="validate" phx-submit="save">
        <.error_summary form={@form} />
        <.input field={@form[:address]} type="textarea" rows="4" label="Mailing address" />
        <.form_actions>
          <.button variant={:success} phx-disable-with="Saving…" disabled={@viewing_as != nil}>
            Save address
          </.button>
          <.button navigate={~p"/teams/#{@current_member.team}/me"}>Cancel</.button>
        </.form_actions>
      </.form>
    </div>
    """
  end
end
