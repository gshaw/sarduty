defmodule Web.MeMobileLive do
  use Web, {:live_view_app_layout, access: :member}

  import Web.MemberLogin

  alias App.Accounts
  alias App.Operation.ChangeOwnPhone
  alias Web.LoginLimit

  # Change mobile number (#156), /teams/:subdomain/me/mobile. Text login uses the mobile
  # number, so a change waits for the code texted to the new number. Codes and wrong
  # codes count against the login limits for that number, as events with
  # `via: "confirm"`. A code waiting for an answer shows its form, even after a reload. A
  # team admin viewing as the member (#425) sees the page with sending turned off.
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign(:page_title, "Change mobile number")
      |> assign(:member, socket.assigns.current_member)
      |> assign(:client_ip, session["client_ip"])
      |> assign(:user_agent, get_connect_info(socket, :user_agent))
      |> assign(:text_login?, Accounts.text_login?())
      |> assign(:phone_form, to_form(%{"phone" => ""}, as: "phone"))
      |> assign_pending(pending(socket.assigns))

    {:ok, socket}
  end

  # The phone change waiting for a code is the logged-in user's, so a team admin viewing
  # as a member never sees their own.
  defp pending(%{viewing_as: nil, current_user: user}), do: ChangeOwnPhone.pending(user)
  defp pending(_assigns), do: nil

  defp assign_pending(socket, e164) do
    socket
    |> assign(:pending, e164)
    |> assign(:code_form, to_form(%{"code" => ""}, as: "confirm"))
  end

  def handle_event("send", %{"phone" => %{"phone" => input}}, socket) do
    %{client_ip: ip} = socket.assigns
    allowed? = &LoginLimit.request(socket.assigns, {:phone, &1}, ip, "confirm")

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
           do: {:error, :blocked},
           else: ChangeOwnPhone.confirm(member, user, e164, code, DateTime.utc_now())

       confirmed(socket, member, who, ip, result)
     end)}
  end

  def handle_event("cancel", _params, socket) do
    {:noreply,
     with_login(socket, fn _member ->
       :ok = ChangeOwnPhone.cancel(socket.assigns.current_user)
       assign_pending(socket, nil)
     end)}
  end

  defp confirmed(socket, member, {:phone, e164}, _ip, {:ok, _member}) do
    message =
      if ChangeOwnPhone.shared?(member, e164, DateTime.utc_now()),
        do:
          "Your mobile number is changed. Another member has it too, so login codes cannot go to it by text.",
        else: "Your mobile number is changed. Login codes by text go to it now."

    socket |> put_flash(:info, message) |> push_navigate(to: ~p"/teams/#{member.team}/me")
  end

  # Tries after a block aren't recorded, as on the login page.
  defp confirmed(socket, _member, who, ip, {:error, reason})
       when reason in [:wrong_code, :blocked] do
    if reason == :wrong_code,
      do: LoginLimit.miss(socket.assigns, who, ip, %{via: "confirm", known_browser: false})

    put_flash(socket, :error, "That code is wrong or expired. Check it, or ask for a new one.")
  end

  defp confirmed(socket, _member, _who, _ip, {:error, text}), do: put_flash(socket, :error, text)

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Your membership" path={~p"/teams/#{@current_member.team}/me"} />
      <:item label="Change mobile number" />
    </.breadcrumbs>
    <div class="measure">
      <h1 class="title">Change mobile number</h1>
      <.phone_content
        member={@member}
        pending={@pending}
        code_form={@code_form}
        phone_form={@phone_form}
        text_login?={@text_login?}
        viewing_as?={@viewing_as != nil}
      />
    </div>
    """
  end

  # Viewing as the member, the buttons are greyed out; Web.UserAuth refuses their events.
  defp phone_content(%{pending: nil} = assigns) do
    ~H"""
    <p class="lead">
      Login codes by text go to this number. A change is saved once you enter the code we text to the new one.
    </p>
    <dl>
      <dt>Mobile number</dt>
      <dd id="current-phone">{Service.Phone.format(@member.phone) || "None"}</dd>
    </dl>
    <.form :if={@text_login?} for={@phone_form} id="phone-form" phx-submit="send">
      <.input field={@phone_form[:phone]} type="tel" label="New mobile number" required>
        Include the area code, like 604-555-1234.
      </.input>
      <.form_actions>
        <.button phx-disable-with="Sending…" disabled={@viewing_as?}>Send code</.button>
        <.button navigate={~p"/teams/#{@member.team}/me"}>Cancel</.button>
      </.form_actions>
    </.form>
    <p :if={!@text_login?} id="phone-off" class="hint">
      SAR Duty cannot send texts right now. Ask a team admin to change your mobile number.
    </p>
    """
  end

  defp phone_content(assigns) do
    ~H"""
    <.form for={@code_form} id="code-form" phx-submit="confirm">
      <p id="code-sent">Enter the code we texted to {Service.Phone.format(@pending)}.</p>
      <.input
        field={@code_form[:code]}
        label="Code"
        inputmode="numeric"
        autocomplete="one-time-code"
        required
      />
      <div id="code-webotp" phx-hook="WebOTP" />
      <.form_actions>
        <.button variant={:success} phx-disable-with="Checking…">Confirm code</.button>
        <.button id="cancel-code" type="button" phx-click="cancel">Cancel</.button>
      </.form_actions>
    </.form>
    """
  end
end
