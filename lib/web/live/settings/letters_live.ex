defmodule Web.Settings.LettersLive do
  use Web, :live_view_app_layout

  import Web.Components.FileDrop
  import Web.Components.TeamSettingsTabs

  alias App.Model.Team
  alias App.Operation.SaveTeamLetterSettings
  alias App.Operation.SaveTeamSignature

  # Settings' Tax credit letters tab, /teams/:subdomain/settings/letters: what every
  # letter prints about the team and who signs it. Hours tags, which decide the hours,
  # are their own tab.
  def mount(_params, _session, socket) do
    team = socket.assigns.current_team

    socket =
      socket
      |> assign(page_title: "Team settings · Tax credit letters", signature_error: nil)
      |> assign_form(Team.build_letters_changeset(team))
      |> allow_upload(:signature,
        accept: ~w(.png .jpg .jpeg),
        max_entries: 1,
        max_file_size: 5_000_000
      )

    {:ok, socket}
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "form"))

  def handle_event("validate", %{"form" => params}, socket) do
    changeset = Team.build_letters_changeset(socket.assigns.current_team, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    signature = consume_signature(socket)

    with {:ok, team} <- SaveTeamLetterSettings.call(socket.assigns.current_team, params),
         {:ok, team} <- save_signature(team, signature) do
      socket =
        socket
        |> assign(current_team: team, signature_error: nil)
        |> assign_form(Team.build_letters_changeset(team))
        |> put_flash(:info, "Team settings saved.")

      {:noreply, socket}
    else
      {:error, :image} ->
        {:noreply, assign(socket, signature_error: "Use a PNG or JPEG image of the signature.")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :signature, ref)}

  def handle_event("remove_signature", _params, socket) do
    {:ok, team} = SaveTeamSignature.call(socket.assigns.current_team, nil)
    {:noreply, socket |> assign(current_team: team) |> put_flash(:info, "Signature removed.")}
  end

  defp consume_signature(socket) do
    case consume_uploaded_entries(socket, :signature, fn %{path: path}, _entry ->
           {:ok, File.read!(path)}
         end) do
      [bytes] -> bytes
      [] -> nil
    end
  end

  # No upload keeps the saved signature; only the remove button clears it.
  defp save_signature(team, nil), do: {:ok, team}
  defp save_signature(team, bytes), do: SaveTeamSignature.call(team, bytes)

  def render(assigns) do
    ~H"""
    <.team_settings_tabs team={@current_team} current={:letters} />
    <div class="measure">
      <p class="lead">What every tax credit letter prints about your team, and who signs it.</p>
      <p class="mb-6">Letters already made keep what they printed.</p>
      <.form for={@form} id="letter-settings-form" phx-submit="save" phx-change="validate">
        <.error_summary form={@form} />
        <.input field={@form[:mailing_address]} label="Mailing address" type="textarea" rows="6" />
        <.input
          field={@form[:authorized_by_name]}
          label="Tax credit letters authorized by"
          type="textarea"
          rows="6"
        >
          The full name of your team president, or someone in a similar role. The CRA uses
          this during tax audits.
        </.input>
        <.input field={@form[:authorized_by_title]} label="Signer's title (optional)">
          Printed under the name on tax credit letters, like President.
        </.input>
        <div class="grid md:grid-cols-2 gap-x-6">
          <.input field={@form[:authorized_by_phone]} label="Signer's phone (optional)" />
          <.input
            field={@form[:authorized_by_email]}
            label="Signer's email (optional)"
            type="email"
          />
        </div>
        <.file_drop
          id="team-signature"
          upload={@uploads.signature}
          label="Signer's signature (optional)"
          kinds="a PNG or JPEG"
          errors={if @signature_error, do: [@signature_error], else: []}
        >
          A PNG or JPEG of the signature, on white or transparent. New tax credit letters
          print it above the signer's name.
          <:current :if={@current_team.signature}>
            <div class="flex flex-wrap items-center gap-4">
              <img
                id="signature-preview"
                src={Web.ImageData.png_data_url(@current_team.signature)}
                class="h-16 max-w-xs border border-border-subtle bg-paper p-1"
                alt="The signer's signature"
              />
              <.button
                id="remove-signature"
                type="button"
                phx-click="remove_signature"
                data-confirm="Remove the signature? New tax credit letters go out unsigned until you add one."
              >
                Remove signature
              </.button>
            </div>
          </:current>
        </.file_drop>
        <.form_actions>
          <.button variant={:success} phx-disable-with="Saving…">Save settings</.button>
        </.form_actions>
      </.form>
    </div>
    """
  end
end
