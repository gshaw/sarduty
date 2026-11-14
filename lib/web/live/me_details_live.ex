defmodule Web.MeDetailsLive do
  use Web, {:live_view_app_layout, access: :member, view_events: ["validate"]}

  import Web.Components.CustomFields

  alias App.Accounts
  alias App.Model.CustomField
  alias App.Model.Member
  alias App.Operation.ChangeOwnPhone
  alias App.Operation.SaveOwnDetails
  alias App.ViewModel.MemberDetailsViewModel
  alias Web.LoginLimit

  # A member's contact details (#156, #389), /teams/:subdomain/me/details: their mobile
  # number, then their address and emergency contacts. `member` comes from the login,
  # never from the URL.
  #
  # The address form shows the member's copy, which the sync keeps (#423), and saving
  # sends the change straight to D4H. Text login uses the mobile number, so a change waits
  # for the code texted to the new number. Codes and wrong codes count against the login
  # limits for that number, as events with `via: "confirm"`. A code waiting for an answer
  # shows its form, even after a reload. Members don't change their email here; team
  # admins do, in D4H. A team admin viewing as the member (#425) sees the page with saving
  # turned off. Invitation reminders are in account settings.
  #
  # Member fields (#1056) are in the same form: the ones D4H sets to `editable` are
  # inputs, saved with Save details on the same row; the `viewable` ones are read only
  # under them. A key that can't fill in fields shows them all read only.
  def mount(_params, session, socket) do
    member = socket.assigns.current_member
    socket = assign(socket, :member, member)

    socket =
      socket
      |> assign(:page_title, "Contact details")
      |> assign_fields(member)
      |> assign(:client_ip, session["client_ip"])
      |> assign(:user_agent, get_connect_info(socket, :user_agent))
      |> assign(:text_login?, Accounts.text_login?())
      |> assign(:phone_form, to_form(%{"phone" => ""}, as: "phone"))
      |> assign_pending(pending(socket.assigns))
      |> assign_form(MemberDetailsViewModel.from_member(member), %{})

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

  defp assign_form(socket, form, params) do
    changeset = MemberDetailsViewModel.changeset(form, params)
    assign(socket, form_data: form, form: to_form(changeset, as: "details"))
  end

  def handle_event("validate", %{"details" => params} = all, socket) do
    socket = keep_field_values(socket, all)

    changeset =
      socket.assigns.form_data
      |> MemberDetailsViewModel.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "details"))}
  end

  def handle_event("save", %{"details" => params} = all, socket) do
    socket = keep_field_values(socket, all)
    fields = all["fields"] || %{}
    {:noreply, with_login(socket, &save(socket, &1, params, fields))}
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

    socket |> put_flash(:info, message) |> push_navigate(to: ~p"/teams/#{member.team}/me/details")
  end

  # Tries after a block aren't recorded, as on the login page.
  defp confirmed(socket, _member, who, ip, {:error, reason})
       when reason in [:wrong_code, :blocked] do
    if reason == :wrong_code,
      do: LoginLimit.miss(socket.assigns, who, ip, %{via: "confirm", known_browser: false})

    put_flash(socket, :error, "That code is wrong or expired. Check it, or ask for a new one.")
  end

  defp confirmed(socket, _member, _who, _ip, {:error, text}), do: put_flash(socket, :error, text)

  # The login is checked again, in case the team turned member logins off since the page
  # opened. A team admin viewing as the member never gets here: Web.UserAuth refuses.
  defp with_login(socket, fun) do
    %{current_user: user, current_member: member} = socket.assigns

    case Member.get_login(user.email, member.id, DateTime.utc_now()) do
      nil -> redirect(socket, to: ~p"/")
      member -> fun.(member)
    end
  end

  defp save(socket, member, params, fields) do
    %{current_user: user, form_data: form} = socket.assigns

    with {:ok, values} <- MemberDetailsViewModel.validate(form, params),
         values = values |> MemberDetailsViewModel.to_values() |> Map.put("fields", fields),
         {:ok, _result} <- SaveOwnDetails.call(member, user, values, DateTime.utc_now()) do
      socket
      |> put_flash(:info, "Your contact details are saved.")
      |> push_navigate(to: ~p"/teams/#{member.team}/me/details")
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        assign(socket, form: to_form(changeset, as: "details"))

      {:error, text} ->
        put_flash(socket, :error, text)
    end
  end

  # The member fields D4H lets a member see (#681): the ones they change as inputs, and
  # the rest read only.
  defp assign_fields(socket, member) do
    editable = SaveOwnDetails.fields(member)
    ids = MapSet.new(editable, & &1.id)

    read_only =
      member.team_id
      |> CustomField.member_fields(:self)
      |> Enum.reject(&MapSet.member?(ids, &1.id))

    assign(socket,
      editable_fields: editable,
      field_values: member.custom_values || %{},
      field_rows: CustomField.rows(read_only, member.custom_values, member.team.timezone)
    )
  end

  # Keeps what was typed when the page renders again, such as after D4H refuses.
  defp keep_field_values(socket, params),
    do: update(socket, :field_values, &Map.merge(&1, params["fields"] || %{}))

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Your membership" path={~p"/teams/#{@current_member.team}/me"} />
      <:item label="Contact details" />
    </.breadcrumbs>
    <div class="measure">
      <h1 class="title">Contact details</h1>
      <p class="lead">
        Changes go to your team's records, where your team admins see them.
      </p>

      <h2 class="heading">Mobile number</h2>
      <.phone_content
        member={@member}
        pending={@pending}
        code_form={@code_form}
        phone_form={@phone_form}
        text_login?={@text_login?}
        viewing_as?={@viewing_as != nil}
      />

      <h2 class="heading mt-8">Mailing address and emergency contacts</h2>

      <.form
        for={@form}
        id="details-form"
        phx-change="validate"
        phx-submit="save"
      >
        <.error_summary form={@form} />
        <.input field={@form[:address]} type="textarea" rows="4" label="Mailing address" />

        <h3 class="subheading mt-6">Emergency contact</h3>
        <.contact_fields
          form={@form}
          fields={[
            :contact1_name,
            :contact1_relation,
            :contact1_primary_phone,
            :contact1_secondary_phone
          ]}
        />
        <h3 class="subheading mt-6">Second emergency contact (optional)</h3>
        <.contact_fields
          form={@form}
          fields={[
            :contact2_name,
            :contact2_relation,
            :contact2_primary_phone,
            :contact2_secondary_phone
          ]}
        />

        <section
          :if={@editable_fields != [] or @field_rows != []}
          id="member-fields"
          class="mt-6"
        >
          <h3 class="subheading">Member fields</h3>
          <.custom_field_inputs fields={@editable_fields} values={@field_values} bundle_tag="h4" />
          <.custom_fields id="own-fields" rows={@field_rows} class="mt-6" />
        </section>

        <.form_actions>
          <.button variant={:success} phx-disable-with="Saving…" disabled={@viewing_as != nil}>
            Save details
          </.button>
        </.form_actions>
      </.form>

      <p id="email-note" class="hint mt-8">
        Your email is {@member.email || "not set"}. Ask a team admin to change it.
      </p>
    </div>
    """
  end

  # Viewing as the member, the buttons are greyed out; Web.UserAuth refuses their events.
  defp phone_content(%{pending: nil} = assigns) do
    ~H"""
    <p id="current-phone">{@member.phone || "None"}</p>
    <p class="hint">
      Login codes by text go to this number. A change is saved once you enter the code we text to the new one.
    </p>
    <.form :if={@text_login?} for={@phone_form} id="phone-form" phx-submit="send">
      <.input field={@phone_form[:phone]} type="tel" label="New mobile number" required>
        Include the area code, like 604-555-1234.
      </.input>
      <.form_actions>
        <.button phx-disable-with="Sending…" disabled={@viewing_as?}>Send code</.button>
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
