defmodule Web.Settings.TeamLogoLive do
  use Web, :live_view_app_layout

  import Web.Components.FileDrop

  alias App.Model.Team
  alias App.Operation.SetTeamLogo
  alias App.Repo

  # Change logo, /teams/:subdomain/settings/logo, from General's Actions (#1075), built
  # like Change photo: the logo, its original to download, a new one to save, and Remove
  # logo. It goes to the team's records, D4H or Records, and SAR Duty keeps its own copy
  # at once (SetTeamLogo). Save, Cancel, and Remove go back to General.
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(page_title: "Change logo")
      |> assign(has_logo: Team.logo_file(socket.assigns.current_team.subdomain) != nil)
      |> assign(
        organization: Repo.preload(socket.assigns.current_team, :organization).organization
      )
      # cspell:ignore webp -- the WebP file extension
      |> allow_upload(:logo,
        accept: ~w(.jpg .jpeg .png .webp),
        max_entries: 1,
        max_file_size: 10_000_000
      )

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Team settings" path={~p"/teams/#{@current_team}/settings"} />
      <:item label="General" path={~p"/teams/#{@current_team}/settings"} />
      <:item label={@page_title} />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>

    <section id="team-logo" class="measure">
      <%= if @has_logo do %>
        <p>
          <img
            id="team-logo-image"
            class="photo-sm object-contain"
            src={Web.TeamController.logo_url(@current_team, :fit)}
            alt="Team logo"
          />
        </p>
        <p>
          <.button id="download-logo" href={~p"/teams/#{@current_team}/settings/logo/original"}>
            Download original logo
          </.button>
        </p>
      <% else %>
        <p id="team-logo-none">
          Your team has no logo. SAR Duty shows its initials in its place.
        </p>
      <% end %>

      <form id="logo-form" class="mt-6" phx-change="validate-logo" phx-submit="save-logo">
        <.file_drop
          id="team-logo-file"
          upload={@uploads.logo}
          label="New logo"
          kinds="a JPEG, PNG, or WebP"
        >
          A JPEG, PNG, or WebP under 10 MB. A PNG with a clear background looks best. ID
          cards, letters, and the Dashboard show it.
        </.file_drop>
        <.logo_previews
          team={@current_team}
          organization={@organization}
          has_logo={@has_logo}
          entry={List.first(@uploads.logo.entries)}
        />
        <.form_actions>
          <.button id="save-logo" variant={:success} phx-disable-with="Saving…">Save logo</.button>
          <.button id="logo-cancel" navigate={~p"/teams/#{@current_team}/settings"}>Cancel</.button>
          <:trailing :if={@has_logo}>
            <.button
              id="remove-logo"
              type="button"
              variant={:danger}
              phx-click="remove-logo"
              phx-disable-with="Removing…"
              data-confirm={"Remove your team's logo? It goes from #{@service} too, and SAR Duty shows your team's initials in its place."}
            >
              Remove logo
            </.button>
          </:trailing>
        </.form_actions>
      </form>
    </section>
    """
  end

  attr :team, :map, required: true
  attr :organization, :map, default: nil
  attr :has_logo, :boolean, required: true
  attr :entry, :any, default: nil, doc: "the file picked, shown before it's saved"

  # Where the logo prints, with the file picked or else the one saved: the top of an ID
  # card, dark, and the top of a tax credit letter, white.
  defp logo_previews(assigns) do
    ~H"""
    <div id="logo-previews" class="logo-previews">
      <figure class="logo-preview">
        <div id="logo-preview-card" class="logo-preview-card">
          <.preview_logo id="logo-preview-card-logo" team={@team} has_logo={@has_logo} entry={@entry} />
          <span>{@team.name}</span>
        </div>
        <figcaption class="hint">
          An ID card. A logo with a clear background, such as a PNG, shows best here.
        </figcaption>
      </figure>
      <figure class="logo-preview">
        <div id="logo-preview-letter" class="logo-preview-letter">
          <span class="whitespace-pre-line">{@team.mailing_address}</span>
          <span class="logo-preview-logos">
            <img
              :if={@organization && @organization.logo_at}
              src={Web.OrganizationController.logo_url(@organization)}
              alt=""
            />
            <.preview_logo
              id="logo-preview-letter-logo"
              team={@team}
              has_logo={@has_logo}
              entry={@entry}
            />
          </span>
        </div>
        <figcaption class="hint">A tax credit letter.</figcaption>
      </figure>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :team, :map, required: true
  attr :has_logo, :boolean, required: true
  attr :entry, :any, default: nil

  defp preview_logo(%{entry: nil, has_logo: false} = assigns), do: ~H""

  defp preview_logo(%{entry: nil} = assigns) do
    ~H"""
    <img id={@id} src={Web.TeamController.logo_url(@team, :fit)} alt="" />
    """
  end

  defp preview_logo(assigns) do
    ~H"""
    <.live_img_preview id={@id} entry={@entry} alt="" />
    """
  end

  def handle_event("validate-logo", _params, socket), do: {:noreply, socket}

  def handle_event("cancel-upload", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :logo, ref)}

  def handle_event("save-logo", _params, socket) do
    case consume_uploaded_entries(socket, :logo, fn %{path: path}, _entry ->
           {:ok, File.read!(path)}
         end) do
      [bytes] -> {:noreply, set_logo(socket, bytes, "Logo saved.")}
      [] -> {:noreply, put_flash(socket, :error, "Select a logo.")}
    end
  end

  def handle_event("remove-logo", _params, socket),
    do: {:noreply, set_logo(socket, nil, "Logo removed.")}

  # Back to General, whose header shows the new logo. A refusal stays here.
  defp set_logo(socket, bytes, text) do
    %{current_team: team, current_user: user} = socket.assigns

    case SetTeamLogo.call(team, bytes, user, DateTime.utc_now()) do
      {:ok, team} ->
        socket
        |> put_flash(:info, text)
        |> push_navigate(to: ~p"/teams/#{team}/settings")

      {:error, text} ->
        put_flash(socket, :error, text)
    end
  end
end
