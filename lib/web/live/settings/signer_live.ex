defmodule Web.Settings.SignerLive do
  use Web, :live_view_app_layout

  import Web.Components.TeamSettingsTabs

  alias App.Model.Team
  alias App.Operation.PrintTaxCreditLetter
  alias App.Operation.SaveTeamSigner

  # Settings' Signer tab, /teams/:subdomain/settings/signer (#995): who signs the team's
  # tax credit letters, with their title, phone, and email. Letters sign with the name
  # typed, "/s/ Alex Chen", so nothing is uploaded. Beside the fields, Every letter ends
  # like this draws the letter's end from what's typed, redrawn on each change and saved
  # only by Save settings. A form is signed by its task leader. The team's address is on
  # General, and the hours tags their own tab.
  def mount(_params, _session, socket) do
    team = socket.assigns.current_team

    socket =
      socket
      |> assign(page_title: "Team settings · Signer")
      # What the letter needs, from its document: a blank one shows in the preview.
      |> assign(needs: PrintTaxCreditLetter.need_names())
      |> assign_form(Team.build_signer_changeset(team))

    {:ok, socket}
  end

  defp assign_form(socket, changeset),
    do: assign(socket, form: to_form(changeset, as: "form"), changeset: changeset)

  def handle_event("validate", %{"form" => params}, socket) do
    changeset = Team.build_signer_changeset(socket.assigns.current_team, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case SaveTeamSigner.call(socket.assigns.current_team, params) do
      {:ok, team} ->
        socket =
          socket
          |> assign(current_team: team)
          |> assign_form(Team.build_signer_changeset(team))
          |> put_flash(:info, "Team settings saved.")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        lines:
          ending(Ecto.Changeset.apply_changes(assigns.changeset), today(assigns), assigns.needs),
        unsaved?: assigns.changeset.changes != %{}
      )

    ~H"""
    <.team_settings_tabs team={@current_team} current={:signer} />
    <p class="lead">Who signs your team's tax credit letters.</p>
    <p class="mb-6">
      A form is signed by its task leader. Letters already emailed keep what they printed.
    </p>
    <div class="signer-layout">
      <.form for={@form} id="signer-form" phx-submit="save" phx-change="validate">
        <.error_summary form={@form} />
        <.input field={@form[:authorized_by_name]} label="Signer">
          The full name of your team president, or someone in a similar role. The CRA may
          call them about a letter.
        </.input>
        <.input field={@form[:authorized_by_title]} label="Signer's title">
          Printed under the name, like President.
        </.input>
        <div class="grid md:grid-cols-2 gap-x-6">
          <.input field={@form[:authorized_by_phone]} label="Phone (optional)" />
          <.input field={@form[:authorized_by_email]} label="Email (optional)" type="email" />
        </div>
        <.form_actions>
          <.button variant={:success} phx-disable-with="Saving…">Save settings</.button>
        </.form_actions>
      </.form>
      <aside id="signer-preview" class="signer-preview">
        <h2 class="label mb-2">
          {if @unsaved?,
            do: "Once you save, every letter ends like this",
            else: "Every letter ends like this"}
          <.badge :if={@unsaved?} id="signer-unsaved">Not saved</.badge>
        </h2>
        <div id="signer-letter-end" class="letter-end">
          <%= for {kind, text} <- @lines do %>
            <p :if={kind == :text}>{text}</p>
            <p :if={kind == :signature} class="letter-end-signature">{text}</p>
            <p :if={kind == :needed}><span class="letter-end-needed">{text}: needed</span></p>
          <% end %>
        </div>
        <p id="signer-preview-hint" class="hint mt-2">
          {if @unsaved?,
            do: "Save settings to use it on new letters.",
            else: "Certified on is the day a letter is emailed."}
        </p>
      </aside>
    </div>
    """
  end

  defp today(%{current_team: team}), do: Service.Period.today(DateTime.utc_now(), team.timezone)

  @needed %{"team.signer" => "Signer", "team.signer_title" => "Signer's title"}

  @doc """
  The end of every letter for a team with these signer details, from Certified on down,
  as the letter prints it (priv/documents/tax_credit_letter.txt): each line `{:text,
  line}`, the typed signature `{:signature, "/s/ Alex Chen"}`, or `{:needed, label}`
  where a value the letter `needs` is blank. A blank optional line drops out, as the
  letter's does. `needs` are the letter's names, PrintTaxCreditLetter.need_names/0's.
  """
  def ending(%Team{} = team, %Date{} = today, needs) do
    needed = fn name, value, lines ->
      cond do
        value not in [nil, ""] -> lines
        name in needs -> [{:needed, @needed[name]}]
        true -> []
      end
    end

    name = team.authorized_by_name

    # With no signer and none needed, the letter names the team where the signer goes.
    signer =
      case needed.("team.signer", name, [{:signature, "/s/ #{name}"}, {:text, name}]) do
        [] -> [{:text, team.legal_name}]
        lines -> lines
      end

    [{:text, "Certified on #{Service.Format.date_long(today)}."}] ++
      signer ++
      needed.("team.signer_title", team.authorized_by_title, [{:text, team.authorized_by_title}]) ++
      optional(team.authorized_by_phone) ++ optional(team.authorized_by_email)
  end

  defp optional(value) when value in [nil, ""], do: []
  defp optional(value), do: [{:text, value}]
end
