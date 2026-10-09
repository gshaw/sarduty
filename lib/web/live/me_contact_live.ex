defmodule Web.MeContactLive do
  use Web, :live_view_narrow_layout

  alias App.Accounts
  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Operation.ChangeOwnContact
  alias Web.LoginLimit

  # A member's email and mobile number (#156), /teams/:subdomain/me/contact. Both are how
  # they log in, so a change waits for the code sent to the new one. Sending a code
  # happens here; the code itself posts to Web.MeContactController, which can move the
  # session to a new email. A code waiting for an answer shows its form, even after a
  # reload.
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign(:page_title, "Your email and mobile number")
      |> assign(:client_ip, session["client_ip"])
      |> assign(:text_login?, Accounts.text_login?())
      |> assign(:trigger_submit, false)
      |> assign_pending(ChangeOwnContact.pending(socket.assigns.current_user))
      |> assign(:email_form, to_form(%{"email" => ""}, as: "email"))
      |> assign(:phone_form, to_form(%{"phone" => ""}, as: "phone"))

    {:ok, socket}
  end

  defp assign_pending(socket, sent_to) do
    socket
    |> assign(:pending, sent_to)
    |> assign(:code_form, to_form(%{"sent_to" => sent_to, "code" => ""}, as: "confirm"))
  end

  def handle_event("send-email", %{"email" => %{"email" => input}}, socket),
    do: {:noreply, request(socket, :email, input)}

  def handle_event("send-phone", %{"phone" => %{"phone" => input}}, socket),
    do: {:noreply, request(socket, :phone, input)}

  def handle_event("cancel", _params, socket) do
    :ok = ChangeOwnContact.cancel(socket.assigns.current_user)
    {:noreply, assign_pending(socket, nil)}
  end

  def handle_event("confirm", %{"confirm" => params}, socket) do
    {:noreply, assign(socket, code_form: to_form(params, as: "confirm"), trigger_submit: true)}
  end

  # The login is checked again, in case the team turned member logins off since the page
  # opened.
  defp request(socket, kind, input) do
    %{current_user: user, member: member, client_ip: ip} = socket.assigns
    allowed? = fn sent_to -> kind |> who(sent_to) |> LoginLimit.check(ip) == :ok end

    with %Member{} = member <- Member.get_login(user.email, member.id, DateTime.utc_now()),
         {:ok, sent_to} <- ChangeOwnContact.request(member, user, kind, input, allowed?) do
      assign_pending(socket, sent_to)
    else
      nil -> redirect(socket, to: ~p"/")
      {:error, text} -> put_flash(socket, :error, text)
    end
  end

  defp who(:phone, e164), do: {:phone, e164}
  defp who(:email, email), do: email

  defp display("+" <> _digits = e164), do: Service.Phone.format(e164)
  defp display(email), do: email

  def render(assigns) do
    ~H"""
    <div>
      <.back_link navigate={~p"/teams/#{@member.team}/me"}>{@member.team.name}</.back_link>
      <h1 class="heading">Your email and mobile number</h1>
      <p class="lead">
        You log in to SAR Duty with these. A change goes to {service(@member)} once you enter
        the code we send to the new one.
      </p>

      <%= if @pending do %>
        <.form
          for={@code_form}
          id="code-form"
          action={~p"/teams/#{@member.team}/me/contact/confirm"}
          phx-submit="confirm"
          phx-trigger-action={@trigger_submit}
        >
          <p id="code-sent">Enter the code we sent to {display(@pending)}.</p>
          <input type="hidden" name={@code_form[:sent_to].name} value={@pending} />
          <.input
            field={@code_form[:code]}
            label="Code"
            inputmode="numeric"
            autocomplete="one-time-code"
            required
          />
          <.form_actions>
            <.button variant={:success} phx-disable-with="Checking…">Confirm code</.button>
            <.button id="cancel-code" type="button" phx-click="cancel">Cancel</.button>
          </.form_actions>
        </.form>
      <% else %>
        <h2 class="subheading mt-8">Email</h2>
        <p id="current-email">{@member.email || "None in #{service(@member)}"}</p>
        <.form for={@email_form} id="email-form" phx-submit="send-email">
          <.input
            field={@email_form[:email]}
            type="email"
            label="New email"
            autocomplete="email"
            required
          />
          <.form_actions>
            <.button phx-disable-with="Sending…">Send code</.button>
          </.form_actions>
        </.form>

        <h2 class="subheading mt-8">Mobile number</h2>
        <p id="current-phone">{@member.phone || "None in #{service(@member)}"}</p>
        <.form :if={@text_login?} for={@phone_form} id="phone-form" phx-submit="send-phone">
          <.input field={@phone_form[:phone]} type="tel" label="New mobile number" required>
            Include the area code, like 604-555-1234.
          </.input>
          <.form_actions>
            <.button phx-disable-with="Sending…">Send code</.button>
          </.form_actions>
        </.form>
        <p :if={!@text_login?} id="phone-off" class="hint">
          SAR Duty cannot send texts right now. Ask a team admin to change your mobile number.
        </p>
      <% end %>
    </div>
    """
  end

  defp service(member), do: D4H.service_name(member.team)
end
