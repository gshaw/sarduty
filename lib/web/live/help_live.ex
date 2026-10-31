defmodule Web.HelpLive do
  use Web,
      {:live_view_app_layout, access: :team, view_events: ["validate"], member_events: ["send"]}

  import Web.Components.Phone, only: [phone: 1]

  alias App.Mailer.HelpMailer
  alias App.Model.Member
  alias App.Operation.SendHelpMessage
  alias App.ViewModel.HelpFormViewModel

  # Get help (#780), /teams/:subdomain/help, from the team picker: a form that sends one
  # email to the team's contacts, the SAR Duty site admins, or both, and the people to
  # ask beside it. A team with no contacts can't be ticked; nothing falls back to every
  # team admin. `?from=` is the page the picker was opened on, for the email's footer.
  def mount(params, _session, socket) do
    team = socket.assigns.current_team
    contacts = Member.get_team_contacts(team, DateTime.utc_now())

    socket
    |> assign(page_title: "Get help", contacts: contacts, sent: nil)
    |> assign(site_admins: App.Support.site_admins())
    |> assign(from: params |> Map.get("from") |> local_path())
    |> assign(user_agent: user_agent(socket))
    |> new_form()
    |> then(&{:ok, &1})
  end

  defp user_agent(socket), do: if(connected?(socket), do: get_connect_info(socket, :user_agent))

  # Only a path on this site, so the email's link can't point anywhere else.
  defp local_path("/" <> rest = path) do
    if String.starts_with?(rest, ["/", "\\"]), do: nil, else: path
  end

  defp local_path(_other), do: nil

  # A fresh form: the team ticked when it has contacts, else the site admins.
  defp new_form(socket) do
    contacts? = socket.assigns.contacts != []

    changeset =
      contacts? |> HelpFormViewModel.new() |> HelpFormViewModel.changeset(%{}, contacts?)

    assign(socket, form: to_form(changeset, as: "help"))
  end

  def render(assigns) do
    ~H"""
    <h1 class="title">Get help</h1>
    <p class="lead measure">
      Ask your team about your hours, activities, and ID card. Ask the SAR Duty site admins when
      something in the app isn't working.
    </p>

    <div class="membership mt-6">
      <div class="min-w-0">
        <.banner :if={@sent} id="help-sent" kind={:success} title={"Sent to #{@sent.went_to}"}>
          <p>Replies come to your email, {@sent.email}. You have a copy there too.</p>
        </.banner>

        <.form for={@form} id="help-form" phx-change="validate" phx-submit="send">
          <.error_summary form={@form} />
          <.send_to form={@form} team={@current_team} contacts={@contacts} site_admins={@site_admins} />
          <.input field={@form[:message]} type="textarea" rows="6" label="Message">
            They get your name, your email to reply to, and the page you came from.
          </.input>
          <.form_actions>
            <.button
              id="help-send"
              variant={:success}
              disabled={@viewing_as != nil}
              phx-disable-with="Sending…"
            >
              Send message
            </.button>
            <.button id="help-cancel" navigate={@from || ~p"/teams/#{@current_team}"}>Cancel</.button>
          </.form_actions>
        </.form>
      </div>

      <aside class="membership-aside">
        <div id="people-to-ask" class="membership-aside-bottom">
          <.people_to_ask team={@current_team} contacts={@contacts} site_admins={@site_admins} />
        </div>
      </aside>
    </div>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :team, :map, required: true
  attr :contacts, :list, required: true
  attr :site_admins, :list, required: true

  # Checkboxes, one line each: who gets it and what it's for. A team with no contacts is
  # greyed out and can't be ticked.
  defp send_to(assigns) do
    field = assigns.form[:to]

    assigns =
      assign(assigns,
        field: field,
        to: List.wrap(field.value),
        errors: Enum.map(field.errors, &translate_error/1),
        site_admins: assigns.site_admins |> Enum.map(& &1.name) |> Service.Format.and_list()
      )

    ~H"""
    <fieldset id="help-to" class={["mb-6", @errors != [] && "field-error"]}>
      <legend class="label mb-1">Send to</legend>
      <.hint>
        {if @contacts == [],
          do: "Only the SAR Duty site admins for now.",
          else: "Select one or both. Everyone it goes to sees who else got it."}
      </.hint>
      <.error :for={msg <- @errors}>{msg}</.error>
      <input type="hidden" name={@field.name <> "[]"} value="" />
      <label class={["choice mb-3", @contacts == [] && "is-off"]}>
        <input
          type="checkbox"
          id="help-to-team"
          name={@field.name <> "[]"}
          value="team"
          checked={@contacts != [] and "team" in @to}
          disabled={@contacts == []}
        />
        <span>
          <strong>{@team.name}</strong>
          <span :if={@contacts != []} class="hint block">
            {@contacts |> Enum.map(& &1.name) |> Service.Format.and_list()}
          </span>
          <span class="hint block">
            {if @contacts == [],
              do: "No team contacts yet. A team admin picks them in Team settings.",
              else: "Your hours, activities, ID card, or anything about the team."}
          </span>
        </span>
      </label>
      <label class="choice mb-3">
        <input
          type="checkbox"
          id="help-to-site-admins"
          name={@field.name <> "[]"}
          value="site_admins"
          checked={"site_admins" in @to}
        />
        <span>
          <strong>SAR Duty site admins</strong>
          <span class="hint block">{@site_admins}</span>
          <span class="hint block">
            Something in the app is broken or confusing, or an idea.{if @contacts == [],
              do: " They can pass a team question on to your team admins."}
          </span>
        </span>
      </label>
    </fieldset>
    """
  end

  attr :team, :map, required: true
  attr :contacts, :list, required: true
  attr :site_admins, :list, required: true

  # Grouped by who they answer for, with Email, and Call and Text on a phone, under each
  # name.
  defp people_to_ask(assigns) do
    assigns = assign(assigns, site_admins: Enum.with_index(assigns.site_admins))

    ~H"""
    <h2 class="subheading">People to ask</h2>
    <section id="help-team-contacts" class="help-group">
      <h3 class="caps mb-2">{@team.name}, team contacts</h3>
      <p :if={@contacts == []} class="hint">
        None yet. Its team admins are asked to pick them on their dashboard.
      </p>
      <ul :if={@contacts != []} class="help-people">
        <li :for={contact <- @contacts} id={"help-contact-#{contact.id}"}>
          <div class="label">{contact.name}</div>
          <div><.email id={"help-contact-#{contact.id}-email"} email={contact.email} /></div>
          <div>
            <.phone
              id={"help-contact-#{contact.id}-phone"}
              phone={contact.phone}
              call_and_text
              class="mt-2"
            />
          </div>
        </li>
      </ul>
    </section>
    <section id="help-site-admins" class="help-group">
      <h3 class="caps mb-2">SAR Duty site admins</h3>
      <ul class="help-people">
        <li :for={{admin, i} <- @site_admins} id={"help-site-admin-#{i}"}>
          <div class="label">{admin.name}</div>
          <div><.email id={"help-site-admin-#{i}-email"} email={admin.email} /></div>
        </li>
      </ul>
    </section>
    """
  end

  def handle_event("validate", %{"help" => params}, socket) do
    form = socket.assigns.form.source.data
    changeset = HelpFormViewModel.changeset(form, params, socket.assigns.contacts != [])
    {:noreply, assign(socket, form: to_form(Map.put(changeset, :action, :validate), as: "help"))}
  end

  def handle_event("send", %{"help" => params}, socket) do
    %{current_team: team, current_user: user} = socket.assigns
    sender = %{name: sender_name(socket.assigns), email: user.email}

    about = %{
      page: page_url(socket.assigns.from),
      device: Service.UserAgent.describe(socket.assigns.user_agent)
    }

    case SendHelpMessage.call(team, sender, params, about) do
      {:ok, to} ->
        socket
        |> assign(sent: %{went_to: HelpMailer.went_to(to), email: user.email})
        |> new_form()
        |> then(&{:noreply, &1})

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "help"))}

      {:error, _reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "The message did not send. Try again, or email #{App.Support.email()}."
         )}
    end
  end

  # The sender's member name on this team, else nil, and the email says their email.
  defp sender_name(%{current_member: %Member{name: name}}), do: name
  defp sender_name(_assigns), do: nil

  defp page_url(nil), do: nil
  defp page_url(path), do: Web.Endpoint.url() <> path
end
