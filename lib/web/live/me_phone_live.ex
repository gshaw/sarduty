defmodule Web.MePhoneLive do
  use Web, :live_view_narrow_layout

  alias App.Accounts
  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Operation.ChangeOwnPhone
  alias Web.LoginLimit

  # A member's mobile number (#156), /teams/:subdomain/me/mobile. Text login uses it, so
  # a change waits for the code texted to the new number. Codes count against the login
  # limits for that number. A code waiting for an answer shows its form, even after a
  # reload. Members don't change their email here; team admins do, in D4H.
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign(:page_title, "Your mobile number")
      |> assign(:client_ip, session["client_ip"])
      |> assign(:text_login?, Accounts.text_login?())
      |> assign(:phone_form, to_form(%{"phone" => ""}, as: "phone"))
      |> assign_pending(ChangeOwnPhone.pending(socket.assigns.current_user))

    {:ok, socket}
  end

  defp assign_pending(socket, e164) do
    socket
    |> assign(:pending, e164)
    |> assign(:code_form, to_form(%{"code" => ""}, as: "confirm"))
  end

  def handle_event("send", %{"phone" => %{"phone" => input}}, socket) do
    %{client_ip: ip} = socket.assigns
    allowed? = fn e164 -> LoginLimit.check({:phone, e164}, ip) == :ok end

    {:noreply,
     with_login(socket, fn member ->
       case ChangeOwnPhone.request(member, socket.assigns.current_user, input, allowed?) do
         {:ok, e164} -> assign_pending(socket, e164)
         {:error, text} -> put_flash(socket, :error, text)
       end
     end)}
  end

  def handle_event("confirm", %{"confirm" => %{"code" => code}}, socket) do
    %{client_ip: ip, pending: e164, current_user: user} = socket.assigns
    who = {:phone, e164}

    {:noreply,
     with_login(socket, fn member ->
       result =
         if LoginLimit.guessing_blocked?(who, ip),
           do: {:error, :wrong_code},
           else: ChangeOwnPhone.confirm(member, user, e164, code, DateTime.utc_now())

       confirmed(socket, member, who, ip, result)
     end)}
  end

  def handle_event("cancel", _params, socket) do
    :ok = ChangeOwnPhone.cancel(socket.assigns.current_user)
    {:noreply, assign_pending(socket, nil)}
  end

  defp confirmed(socket, member, {:phone, e164}, _ip, {:ok, _member}) do
    message =
      if ChangeOwnPhone.shared?(member, e164, DateTime.utc_now()),
        do: "Your mobile number is changed. Another member has it too, so text login won't work.",
        else: "Your mobile number is changed. Login codes by text go to it now."

    socket |> put_flash(:info, message) |> push_navigate(to: ~p"/teams/#{member.team}/me")
  end

  defp confirmed(socket, _member, who, ip, {:error, :wrong_code}) do
    LoginLimit.miss(who, ip)
    put_flash(socket, :error, "That code is wrong or expired. Check it, or ask for a new one.")
  end

  defp confirmed(socket, _member, _who, _ip, {:error, text}), do: put_flash(socket, :error, text)

  # The login is checked again, in case the team turned member logins off since the page
  # opened.
  defp with_login(socket, fun) do
    %{current_user: user, member: member} = socket.assigns

    case Member.get_login(user.email, member.id, DateTime.utc_now()) do
      nil -> redirect(socket, to: ~p"/")
      member -> fun.(member)
    end
  end

  def render(assigns) do
    ~H"""
    <div>
      <.back_link navigate={~p"/teams/#{@member.team}/me"}>{@member.team.name}</.back_link>
      <h1 class="heading">Your mobile number</h1>
      <p class="lead">
        Login codes by text go to this number. A change goes to {service(@member)} once you
        enter the code we text to the new one.
      </p>

      <%= if @pending do %>
        <.form for={@code_form} id="code-form" phx-submit="confirm">
          <p id="code-sent">Enter the code we texted to {Service.Phone.format(@pending)}.</p>
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
        <p id="current-phone">{@member.phone || "None in #{service(@member)}"}</p>
        <.form :if={@text_login?} for={@phone_form} id="phone-form" phx-submit="send">
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

      <p id="email-note" class="hint mt-8">
        Your email is {@member.email || "not set"}. Ask a team admin to change it.
      </p>
    </div>
    """
  end

  defp service(member), do: D4H.service_name(member.team)
end
